import Config

# Serves the digested static files listed in the manifest `mix assets.deploy` writes.
config :lanternhall, LanternhallWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Do not print debug messages in production
config :logger, level: :info

# What prod reads from the environment at boot is in config/runtime.exs.
