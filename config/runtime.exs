import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/lanternhall start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# Install config (SPEC-platform.md section 3.1), validated here so a bad value stops
# boot before any app starts. Dev and test default to the synthetic personal example,
# so they never read a real install's config.
install_env =
  if config_env() in [:dev, :test] and System.get_env("LANTERNHALL_CONFIG", "") == "" do
    Map.put(
      System.get_env(),
      "LANTERNHALL_CONFIG",
      Path.expand("install/personal.example.exs", __DIR__)
    )
  else
    System.get_env()
  end

install =
  Lanternhall.Platform.Config.load!(Lanternhall.Platform.Config.path(install_env), install_env)

config :lanternhall, :install, install

if System.get_env("PHX_SERVER") do
  config :lanternhall, LanternhallWeb.Endpoint, server: true
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :lanternhall, LanternhallWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/lanternhall_web/router\.ex$"E,
        ~r"lib/lanternhall_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/lanternhall/lanternhall.db
      """

  config :lanternhall, Lanternhall.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Dev and test keep fixed ports (4000, 4002); prod serves on the install's port.
  port = install.port

  config :lanternhall, LanternhallWeb.Endpoint,
    url: [host: "localhost", port: port, scheme: "http"],
    http: [port: port],
    check_origin: ["//localhost:#{port}"],
    secret_key_base: secret_key_base
end
