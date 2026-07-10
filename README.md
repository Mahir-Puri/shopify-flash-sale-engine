# Shopify Flash Sale Engine

A Rails 7 application that runs limited-inventory flash sales without overselling. Buyers reserve units through a Redis-only hot path, abandoned reservations release automatically, and confirmed purchases arrive through verified, idempotent Shopify webhooks.

The problem this solves: 100 units go on sale at noon, 5,000 people hit "buy" in the first second. A naive `SELECT ... FOR UPDATE` on an inventory row turns the database into a queue and the sale into a timeout festival. This system keeps the database out of the critical path entirely and pushes the concurrency problem into a single atomic Redis script.
