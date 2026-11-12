# Compile-time configuration shared by every environment. The environment's own file
# (dev.exs, test.exs or prod.exs) is imported at the bottom and overrides it; runtime.exs
# runs at boot.
import Config

config :lanternhall,
  ecto_repos: [Lanternhall.Repo],
  generators: [timestamp_type: :utc_datetime]

# The composition root (SPEC-platform.md section 3.2): every feature implementation, in
# build order. The only place that names feature modules; platform reads this list.
# Test adds synthetic fixture features from test/support/fixtures/features/ so every
# registry path is tested before real features exist. Config scripts cannot read values
# set earlier, so test.exs could only repeat this list; the branch here keeps one list.
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

# Configure the endpoint
config :lanternhall, LanternhallWeb.Endpoint,
  url: [host: "localhost"],
  # Loopback only, in every environment (SPEC-platform.md section 3.3).
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

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  lanternhall: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  lanternhall: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
