# Example install config for a work machine (SPEC.md section 5 "Config").
# Copy it to ~/.config/lanternhall/config.exs, or point LANTERNHALL_CONFIG at your copy,
# then check it with `mix lanternhall.config.check <path>`.
# Run dev as a work install: LANTERNHALL_CONFIG=config/install/work.example.exs iex -S mix phx.server
# It holds no secrets: credentials live encrypted in the database.
import Config

config :lanternhall, :install,
  # :personal or :work; decides which optional modules may be enabled.
  kind: :work,
  # Port of http://localhost:<port> in prod (dev serves on 4000, test on 4002).
  port: 4100,
  # Optional modules to enable, by module id; core modules are always on.
  modules: [],
  # Optional: absolute path for the database and local backups, for example
  #   data_dir: "/absolute/path/to/lanternhall-data",
  # Default: $XDG_DATA_HOME/lanternhall, else ~/.local/share/lanternhall.
  #
  # Any zone known to the tz package; dates and times display in it.
  time_zone: "Europe/London"
