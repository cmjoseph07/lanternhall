defmodule LanternhallWeb.HealthController do
  use LanternhallWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", version: Lanternhall.version()})
  end
end
