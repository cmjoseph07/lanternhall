import Config

# Runs at boot in every environment, and in a release: after compilation, before any
# app starts. Compile-time settings set here would not take effect.

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

install = Lanternhall.Platform.Config.load!(install_env, Lanternhall.Platform.Features.all())

config :lanternhall, :install, install

# A release serves HTTP only when asked to: `PHX_SERVER=true bin/lanternhall start`.
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

  # Signs and encrypts cookies. Dev and test use the fixed values in their config
  # files; prod reads its own from the environment, so it is never committed.
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
