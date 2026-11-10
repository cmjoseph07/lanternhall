defmodule LanternhallWeb.E2E.Platform.SettingsInstallTest do
  use LanternhallWeb.E2ECase

  test "Settings > Install opens in Chromium, LiveView connects, no console error or CSP violation",
       %{conn: conn} do
    conn
    |> visit(~p"/settings")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("#install-kind", text: "personal")
    |> assert_has("#uptime")
    |> assert_clean_browser()
  end
end
