defmodule LanternhallWeb.HealthController do
  @moduledoc """
  Liveness check used by `rel/install.sh` and `rel/smoke.sh`.
  """
  use LanternhallWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok", version: Lanternhall.version()})
  end
end
