defmodule LanternhallWeb.HealthControllerTest do
  use LanternhallWeb.ConnCase, async: true

  test "GET /healthz answers 200 with status ok and the app version", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert json_response(conn, 200) == %{
             "status" => "ok",
             "version" => Mix.Project.config()[:version]
           }
  end
end
