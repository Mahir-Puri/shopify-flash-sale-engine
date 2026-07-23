FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev libyaml-dev git curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_PATH=/usr/local/bundle \
    RAILS_LOG_TO_STDOUT=1

# Gemfile first so the bundle layer is cached across code changes.
# Gemfile.lock is not committed (see README); the build resolves it.
COPY Gemfile* ./
RUN bundle install --jobs 4 --retry 3

COPY . .

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
