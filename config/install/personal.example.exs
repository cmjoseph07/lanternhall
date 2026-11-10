# Example install config for a personal machine (SPEC.md section 5 "Config").
# Copy it to ~/.config/lanternhall/config.exs, or point LANTERNHALL_CONFIG at your copy,
# then check it with `mix lanternhall.config.check <path>`.
# Dev and test boot with this file unless LANTERNHALL_CONFIG is set.
# It holds no secrets: credentials live encrypted in the database.
import Config

config :lanternhall, :install,
  # :personal or :work; decides which optional modules may be enabled.
  kind: :personal,
  # Port of http://localhost:<port> in prod (dev serves on 4000, test on 4002).
  port: 4100,
  # Optional modules to enable, by module id; core modules are always on.
  modules: [],
  # Optional: absolute path for the database and local backups, for example
  #   data_dir: "/absolute/path/to/lanternhall-data",
  # Default: $XDG_DATA_HOME/lanternhall, else ~/.local/share/lanternhall.
  #
  # Any zone known to the tz package; dates and times display in it.
  time_zone: "America/New_York"
