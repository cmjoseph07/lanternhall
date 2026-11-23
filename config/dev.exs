import Config

config :lanternhall, Lanternhall.Repo,
  database: Path.expand("../lanternhall_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :lanternhall, LanternhallWeb.Endpoint,
  url: [host: "localhost", port: 4000],
  http: [port: 4000],
  check_origin: ["//localhost:4000"],
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "KR7S/DTrNMFiC+Vl56Dv5nvv3fAjOZs922HFT155l1f02fz7KlSaue+L2IV5rO0s",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:lanternhall, ~w(--sourcemap=inline --watch)]},
    # Not Tailwind.install_and_run/2, which runs a download without checking its hash.
    tailwind:
      {Mix.Tasks.Lanternhall.Tailwind.Install, :install_and_run, [:lanternhall, ~w(--watch)]}
  ]

config :lanternhall, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Changing this configuration will require mix clean and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
