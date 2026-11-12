import Config

# The dev database, a file at the repo root.
config :lanternhall, Lanternhall.Repo,
  database: Path.expand("../lanternhall_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# No caching, with debug error pages and code reloading. The watchers rebuild the JS
# and CSS bundles when their sources change.
config :lanternhall, LanternhallWeb.Endpoint,
  url: [host: "localhost", port: 4000],
  http: [port: 4000],
  check_origin: ["//localhost:4000"],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "KR7S/DTrNMFiC+Vl56Dv5nvv3fAjOZs922HFT155l1f02fz7KlSaue+L2IV5rO0s",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:lanternhall, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:lanternhall, ~w(--watch)]}
  ]

# Compiles the LiveDashboard route (lib/lanternhall_web/router.ex).
config :lanternhall, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include debug annotations and locations in rendered markup.
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true
