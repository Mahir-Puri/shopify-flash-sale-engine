# Shopify Flash Sale Engine

A Rails 7 application that runs limited-inventory flash sales without overselling. Buyers reserve units through a Redis-only hot path, abandoned reservations release automatically, and confirmed purchases arrive through verified, idempotent Shopify webhooks.

The problem this solves: 100 units go on sale at noon, 5,000 people hit "buy" in the first second. A naive `SELECT ... FOR UPDATE` on an inventory row turns the database into a queue and the sale into a timeout festival. This system keeps the database out of the critical path entirely and pushes the concurrency problem into a single atomic Redis script.

## Architecture

```
                              ┌─────────────────────────────────────────────┐
                              │                 Rails (Puma)                │
  Buyer ──POST /reserve──────▶│  Api::FlashSalesController#reserve          │
                              │    │                                        │
                              │    │  EVALSHA reserve.lua   (atomic)        │
                              │    ├───────────────────────────────┐        │
                              │    │  perform_async / perform_in   │        │
                              │    ├─────────────────────────┐     │        │
                              └────┼─────────────────────────┼─────┼────────┘
                                   ▼                         ▼     ▼
                              200/409 JSON              ┌──────────────────┐
                                                        │      Redis       │
                                                        │  inventory  DECR │
                                                        │  reservation SET │
                                                        │  sidekiq queues  │
                                                        └────────┬─────────┘
                                                                 │ pull jobs
                                                                 ▼
  ┌──────────────────────────────────────────────────────────────────────────┐
  │                                Sidekiq                                   │
  │                                                                          │
  │  ReservationRecorderWorker ──▶ INSERT reservations row (pending)         │
  │  ReservationExpiryWorker ────▶ release.lua ──▶ INCR inventory,           │
  │        (delayed by timeout)                    mark row expired          │
  │  FlashSaleActivationWorker ──▶ seed inventory + config keys, activate    │
  │  OrderWebhookWorker ─────────▶ confirm reservation, create order,        │
  │                                confirm.lua (disarm expiry), mark event   │
  │                                          │                               │
  └──────────────────────────────────────────┼───────────────────────────────┘
                                             ▼
                                        ┌──────────┐
                                        │ Postgres │  flash_sales, reservations,
                                        └──────────┘  orders, webhook_events
                                             ▲
                              ┌──────────────┴──────────────────────────────┐
  Shopify ──POST /webhooks───▶│  Webhooks::OrdersController#create          │
   orders/create              │   1. HMAC over raw body  ──▶ 401 on fail    │
                              │   2. idempotency check on shopify_order_id  │
                              │   3. enqueue OrderWebhookWorker             │
                              │   4. head :ok                               │
                              └─────────────────────────────────────────────┘
```

The division of labor is strict. The reservation endpoint touches Redis and nothing else. Sidekiq owns every Postgres write that results from a reservation. The webhook endpoint does exactly enough synchronous work to authenticate and deduplicate, then hands off.

### Repository layout

```
app/
├── controllers/
│   ├── api/flash_sales_controller.rb    # create/show sales, the /reserve hot path
│   ├── webhooks/orders_controller.rb    # HMAC gate + idempotency gate + enqueue
│   └── dashboard_controller.rb          # live inventory, reservations, event log
├── models/                              # thin ActiveRecord: enums, scopes, key helpers
├── services/
│   ├── inventory_reservation_service.rb # the three Lua scripts and their runners
│   ├── flash_sale_activator.rb          # scheduled -> active, seeds Redis (NX)
│   ├── order_confirmation_service.rb    # payload -> confirmed reservation + order
│   ├── webhook_verifier.rb              # constant-time HMAC-SHA256 check
│   └── shopify/webhook_registrar.rb     # GraphQL webhookSubscriptionCreate
└── workers/                             # four Sidekiq jobs, all idempotent
spec/
├── services/  workers/  requests/       # unit level
└── integration/                         # full flow, 150-vs-100 oversell, retry sim
loadtest/load_test.py                    # stdlib-only concurrent load driver
```

## The reservation script, and why it is a Lua script

`POST /api/flash_sales/:id/reserve` runs this inside Redis:

```lua
local inventory = redis.call('GET', KEYS[1])          -- flash_sale:{id}:inventory
if not inventory then return {0, 'not_active'} end
if redis.call('EXISTS', KEYS[2]) == 1 then            -- one live hold per buyer
  return {0, 'already_reserved'}
end
if tonumber(inventory) <= 0 then return {0, 'sold_out'} end
local timeout = tonumber(redis.call('HGET', KEYS[3], 'timeout_seconds')) or 300
redis.call('DECR', KEYS[1])
redis.call('SET', KEYS[2], ARGV[1], 'EX', timeout + 60)
return {1, ARGV[1], timeout}
```

Redis executes scripts atomically on its single command thread, so the check and the decrement are one indivisible operation. With separate GET and DECR commands, two requests could both read `inventory = 1`, both pass the check, and both decrement: an oversell. Inside the script that interleaving cannot happen, at any concurrency, without locks, retries, or compare-and-swap loops. The same property gives us duplicate-buyer rejection for free, since the EXISTS check and the SET are also inside the atomic block.

The script reads the sale's timeout from a Redis config hash (seeded at activation) instead of from Postgres, which is what makes the hot path database-free even for reads. A cold sale simply has no inventory key, so `not_active` falls out of the same GET that fetches the count.

Two companion scripts complete the lifecycle, both guarded by a token comparison so they only act on the exact reservation they were issued for:

- `release`: if the reservation key still holds our token, delete it and INCR inventory back. Run by the expiry worker when the timeout elapses.
- `confirm`: if the key still holds our token, delete it without touching inventory. Run by the webhook worker when the order lands. Deleting the key is what disarms the pending expiry job; when it fires later, its token comparison fails and inventory stays down.

The token comparison is the whole trick. Expiry and confirmation can race in either order and the loser always becomes a no-op, because only one of them can be first to delete the key.

Failure direction is chosen deliberately. The reservation key's TTL is set to timeout plus a 60-second grace so the Sidekiq worker (scheduled at exactly the timeout) is the authority for restoring inventory, and the TTL is only a backstop against a lost job. If a worker is lost anyway, a unit leaks: the system undersells. It never oversells.

## Webhook HMAC verification

Shopify signs every webhook by computing HMAC-SHA256 over the raw request body with the app's shared secret and sending the base64 digest in `X-Shopify-Hmac-SHA256`. The controller recomputes it:

```ruby
digest   = OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), secret, request.raw_post)
expected = Base64.strict_encode64(digest)
ActiveSupport::SecurityUtils.secure_compare(expected, header)
```

Two details carry the security weight. The digest runs over the raw bytes, before JSON parsing, because re-serializing a parsed hash changes key order and whitespace and breaks the signature. And the comparison is constant-time; a plain `==` returns early at the first mismatched byte, which leaks match length through response timing and lets an attacker forge a signature byte by byte. Verification happens before any parsing and before any database access, so an unsigned request costs the app one HMAC computation and nothing more.

## Idempotency

Shopify retries any webhook that does not get a 2xx within its deadline, and retries can arrive concurrently. Deduplication is enforced in three layers:

1. A unique index on `webhook_events.shopify_order_id`. If two deliveries race past the controller's initial lookup, exactly one INSERT wins; the loser rescues `RecordNotUnique`, re-reads the existing row, and returns 200.
2. `OrderWebhookWorker` takes a row lock on the event and re-checks `processed?` inside the transaction, so a duplicate enqueued job exits without doing work.
3. `orders.shopify_order_id` is also unique, and confirmation re-checks the reservation's status under a row lock. Even a bug upstream cannot produce two orders for one Shopify order id.

The same discipline applies internally: activation seeds Redis with `SET NX` so a double-fired activation job cannot reset a mid-sale counter, and the recorder worker uses `find_or_create_by!` on the token.

## Setup

Docker is the intended path:

```bash
cp .env.example .env        # optional, compose ships working dev defaults
docker-compose up --build
```

This starts Postgres, Redis, the Rails app on port 3000, and a Sidekiq process. `bin/setup` runs inside the web container: migrations, then a seed that creates and activates a demo flash sale with 100 units, so the API is immediately usable:

```bash
curl -X POST http://localhost:3000/api/flash_sales/1/reserve \
     -H 'Content-Type: application/json' -d '{"buyer_id": "me"}'

curl http://localhost:3000/dashboard
```

To run natively instead: Ruby 3.2, Postgres, and Redis, then `bundle install`, `bin/setup`, `bin/rails s` plus `bundle exec sidekiq -C config/sidekiq.yml`.

Note on `Gemfile.lock`: it is not committed because this repo is produced from a spec rather than a live `bundle install`. The first `bundle install` (or the Docker build) resolves and writes it; commit it at that point as you normally would.

Connecting a real store is optional and only needed for live webhooks. Set `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET`, `SHOPIFY_SHOP_DOMAIN`, `SHOPIFY_ACCESS_TOKEN`, `APP_HOST`, and `SHOPIFY_WEBHOOK_SECRET`, then register the subscription:

```bash
bin/rails shopify:register_webhooks
```

For local testing, the spec suite's helper shows how to sign your own payloads with `SHOPIFY_WEBHOOK_SECRET`.

### Storefront integration note

The webhook worker matches an order to a reservation by the `reservation_token` cart attribute (surfaced in the order's `note_attributes`), falling back to the buyer's Shopify customer id. Whatever storefront calls `/reserve` should attach the returned token to the cart before checkout.

## Tests

```bash
bundle exec rspec
```

The suite needs a local Postgres and Redis (CI provides both as service containers, see `.github/workflows/ci.yml`). Tests use Redis database 1 and flush it between examples, so a dev instance on database 0 is untouched.

Coverage follows the risk: Lua boundary conditions including a 50-thread concurrent decrement, HMAC accept/reject/tamper cases, duplicate webhook delivery, expiry-vs-confirmation races, and two full end-to-end flows. The headline integration test fires 150 concurrent reservations at a 100-unit sale through real Redis and asserts exactly 100 succeed with 100 unique tokens.

## Load test

With the stack up:

```bash
python3 loadtest/load_test.py --requests 500 --concurrency 150
```

Standard library only. It discovers the seeded sale from `/dashboard`, hammers `/reserve` from a thread pool, then reports outcome counts, throughput, and p50/p95/p99 latency, and exits nonzero if successes ever exceed the inventory that was live at the start.

## Benchmark results

To be filled in after running the load test on target hardware.

```
Hardware / environment:
Requests / concurrency:
Successes / sold-out:
Throughput (req/s):
p50 latency:
p95 latency:
p99 latency:
Oversells:
```
