defmodule LanternhallWeb.E2E.Platform.FeatureGateTest do
  use LanternhallWeb.E2ECase

  # LiveView logs a warning for every navigate across live_sessions, and each feature has
  # its own, so the server falls back to a full page load here by design.
  @moduletag :capture_log

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
