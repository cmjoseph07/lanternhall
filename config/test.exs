import Config

config :lanternhall, Lanternhall.Repo,
  database: Path.expand("../lanternhall_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :lanternhall, LanternhallWeb.Endpoint,
  url: [host: "localhost", port: 4002],
  http: [port: 4002],
  check_origin: ["//localhost:4002"],
  secret_key_base: "xxUAB/U3HD+Ud+Xn9HKZsLfjW/4xEpYNQnEfIRzIISlidURDmJVFFGTAN0i9bF9g",
  server: true

config :lanternhall, fixture_routes: true

config :phoenix_test,
  otp_app: :lanternhall,
  playwright: [browser: :chromium]

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
