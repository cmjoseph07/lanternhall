defmodule LanternhallWeb.E2E.Platform.LandingTest do
  use LanternhallWeb.E2ECase

  test "Landing opens in Chromium, LiveView connects, no console error or CSP violation",
       %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#app-version", text: Lanternhall.version())
    |> assert_clean_browser()
  end
end
