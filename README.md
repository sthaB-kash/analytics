# Analytics

A small Rails 8 API-only service that reads GA4 traffic counts from the Google
Analytics Data API and serves them as JSON. It exists so front-end apps can show
visitor numbers without holding Google service-account credentials themselves.

## Requirements

* Ruby 3.3.6 (see `.ruby-version`; use rbenv/rvm/asdf or your version manager of choice)
* SQLite 3.8+ (`sqlite3` CLI and headers — `apt install sqlite3 libsqlite3-dev` on Debian/Ubuntu)
* libvips, for Active Storage variants (`apt install libvips`)
* `config/master.key` — not in git; get it from another developer or a password manager

No separate database server, Redis, or job runner is needed: Solid Cache, Solid
Queue, and Solid Cable all run on SQLite, and development uses an in-memory cache.

## Setup

```bash
bin/setup            # bundle install, db:prepare, clear logs, then start the server
bin/setup --skip-server   # same, without booting the server
```

`bin/setup` is idempotent — re-run it any time to bring your environment up to date.

## Running the server

```bash
bin/dev              # => http://localhost:3000
bin/rails server -p 4000   # bin/dev passes arguments through to `rails server`
```

Verify it is up:

```bash
curl localhost:3000/up                    # Rails health check, 200 when the app boots
curl localhost:3000/                      # {"status":"ok","message":"Google Analytics Service"}
curl localhost:3000/analytics/garirbazar  # the GA4 report
```

## Configuration

All Google credentials live in Rails encrypted credentials, so nothing sensitive
belongs in `.env` or in the repo. Edit them with:

```bash
bin/rails credentials:edit          # development/test, decrypted with config/master.key
bin/rails credentials:edit --environment production
```

The service reads this shape:

```yaml
google_analytics:
  property_id: "426706035"      # GA4 property, numeric, no "properties/" prefix
  client_email: <service account email>
  private_key: "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

Take these three values from the service-account JSON key you download from Google
Cloud. Keep `private_key` on a single line with literal `\n` escapes exactly as it
appears in the JSON — `GoogleAnalyticsService` unescapes them before handing the key
to OpenSSL. The service account must be granted **Viewer** on the GA4 property, and
the Google Analytics Data API must be enabled on its Google Cloud project.

Without a `property_id` the service raises `GoogleAnalyticsService::Error` at
initialization; bad or missing key material surfaces as a `502` from the endpoint
with `{"error":"Analytics data is unavailable right now"}` and the real cause in
`log/development.log`.

`config/master.key` and `config/credentials/production.key` are gitignored. The
`.env` file (also gitignored) only carries `RAILS_ENV` and `RAILS_MASTER_KEY` for
the Docker Compose deployment — local development does not need it.

## API

### `GET /analytics/garirbazar`

Page views and visitors for the last 7 complete days, ending yesterday. Today is
excluded because it is still accumulating. Responses are cached for 15 minutes,
since the Data API is rate limited and a report takes about a second.

```json
{
  "property_id": "426706035",
  "start_date": "2026-08-19",
  "end_date": "2026-08-25",
  "total_page_views": 36667,
  "total_visitors": 17452,
  "days": [
    { "date": "2026-08-19", "page_views": 4955, "visitors": 2246 }
  ]
}
```

`days` always has one entry per day in the range — GA omits zero-traffic days, and
the service fills them in. `total_visitors` is Google's own aggregation, not the sum
of the daily rows: a person who visits on three days counts once in the total but
appears in three rows.

Adding a site means adding a route and a controller action alongside
`analytics#garirbazar`, plus the property id for that site.

## Tests and checks

```bash
bin/rails test                   # full suite
bin/rails test test/services/google_analytics_service_test.rb
bin/rubocop                      # rails-omakase style
bin/brakeman --quiet --no-pager  # static security analysis
bin/bundler-audit                # known CVEs in gems
bin/ci                           # everything above, as CI runs it
```

The tests stub `GoogleAnalyticsService`, so they never call Google and need no
credentials.

## Database

SQLite files live in `storage/` and are gitignored.

```bash
bin/rails db:prepare   # create and migrate
bin/rails db:reset     # drop and recreate from scratch
bin/rails console
```

## Deployment

`Dockerfile` builds a production image (it is not meant for development).
`docker-compose.yml` runs the published image on port 8000, reading `RAILS_ENV` and
`RAILS_MASTER_KEY` from `.env` and mounting `~/analytics_storage` for the SQLite
databases. Kamal config lives in `.kamal/`.
