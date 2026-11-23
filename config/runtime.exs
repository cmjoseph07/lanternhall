import Config

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

if System.get_env("PHX_SERVER") do
  config :lanternhall, LanternhallWeb.Endpoint, server: true
end

if config_env() == :dev do
  config :lanternhall, LanternhallWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
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

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port = install.port

  config :lanternhall, LanternhallWeb.Endpoint,
    url: [host: "localhost", port: port, scheme: "http"],
    http: [port: port],
    check_origin: ["//localhost:#{port}"],
    secret_key_base: secret_key_base
end
