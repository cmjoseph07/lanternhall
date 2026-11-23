import Config

config :lanternhall,
  ecto_repos: [Lanternhall.Repo],
  generators: [timestamp_type: :utc_datetime]

config :lanternhall,
       :features,
       [Lanternhall.Platform.PlatformFeature] ++
         if(config_env() == :test,
           do: [
             Lanternhall.Fixtures.Features.Core,
             Lanternhall.Fixtures.Features.Personal,
             Lanternhall.Fixtures.Features.Work,
             Lanternhall.Fixtures.Features.Integration
           ],
           else: []
         )

# Set explicitly (SPEC.md section 5 "Data layer"). Naming `journal_mode` here
# also makes `mix ecto.create` build the file in WAL mode, so the migrator's
# pooled connections never race to convert it ("database is locked").
config :lanternhall, Lanternhall.Repo,
  journal_mode: :wal,
  busy_timeout: 2000

config :lanternhall, LanternhallWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LanternhallWeb.ErrorHTML, json: LanternhallWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Lanternhall.PubSub,
  live_view: [signing_salt: "B/c52piV"]

# Browsers send a host's cookies to every port on it, so dev, test and prod on one
# machine each need their own session cookie, or they overwrite each other's session
# and CSRF token.
config :lanternhall, :session_cookie, "_lanternhall_#{config_env()}"

config :phoenix_live_view,
  root_tag_attribute: "phx-r"

config :esbuild,
  version: "0.25.4",
  lanternhall: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.3",
  # The package's check runs the binary (`--help`) when the app starts, to read its
  # version. The SHA-256 below pins the version too, and is checked before any run.
  version_check: false,
  lanternhall: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :lanternhall, :tailwind_sha256, %{
  "linux-arm64" => "55fd0b241214eff3de1e8ee4f22796662f2d2e7a49bcfca7477cfd0bac398195",
  "linux-x64" => "dc61b3ac6b8c9ca874c0cc4c57b2409791a64c5540404ca5f5367360babc313a",
  "macos-arm64" => "cdf646702987a743464dff4d9c60fd4480d1c1e73dd819a9a67f1078815dce9d",
  "macos-x64" => "7922e0953f2110c05976e3bf58f14e643d90427575e766b7d433f5f80cbee7e1"
}

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
