defmodule LanternhallWeb.E2E.Platform.NavigationTest do
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright

  # A value set on `window` lives as long as the document, so it survives a live
  # navigation and is gone after a full page load.
  test "moving between a feature's page and a platform page keeps the document, back included",
       %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate("window.__doc = 1")
    |> click_link("header a", "Lanternhall")
    |> assert_path(~p"/")
    |> assert_has("#app-version")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate("window.__doc", &assert(&1 == 1))
    |> Playwright.evaluate("history.back()")
    |> assert_path(~p"/fixtures/core")
    |> assert_has("#fixture-core")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate("window.__doc", &assert(&1 == 1))
  end
end
