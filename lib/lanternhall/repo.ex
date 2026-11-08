defmodule Lanternhall.Repo do
  use Ecto.Repo,
    otp_app: :lanternhall,
    adapter: Ecto.Adapters.SQLite3
end
