defmodule LanternhallWeb.E2E.Platform.FeatureGateTest do
  use LanternhallWeb.E2ECase

  # The browser reports the 404 as a console error, which the Playwright driver logs.
  @tag :capture_log
  test "following a live link into a disabled feature lands on the plain 404 page",
       %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core")
    |> assert_has("[data-phx-main].phx-connected")
    |> click_link("#to-fixture-personal", "Disabled fixture page")
    |> assert_path(~p"/fixtures/personal")
    |> assert_has("body", text: "Not Found", exact: true)
    |> assert_clean_browser(
      expect_errors: [
        "Failed to load resource: the server responded with a status of 404 (Not Found)"
      ]
    )
  end
end
