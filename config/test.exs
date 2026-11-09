import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :lanternhall, Lanternhall.Repo,
  database: Path.expand("../lanternhall_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# The server runs during tests so real-browser E2E tests (`mix test --only e2e`)
# can open http://localhost:4002.
config :lanternhall, LanternhallWeb.Endpoint,
  url: [host: "localhost", port: 4002],
  http: [port: 4002],
  check_origin: ["//localhost:4002"],
  secret_key_base: "xxUAB/U3HD+Ud+Xn9HKZsLfjW/4xEpYNQnEfIRzIISlidURDmJVFFGTAN0i9bF9g",
  server: true

# Real-browser E2E tests: PhoenixTest driven through Playwright's Chromium,
# installed under assets/node_modules by `pnpm --dir assets install`.
config :phoenix_test,
  otp_app: :lanternhall,
  playwright: [browser: :chromium]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
