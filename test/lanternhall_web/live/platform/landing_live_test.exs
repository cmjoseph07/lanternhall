defmodule LanternhallWeb.Platform.LandingLiveTest do
  use LanternhallWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the landing stub with the app version", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "h1", "Lanternhall")
    assert has_element?(view, "#app-version", Mix.Project.config()[:version])
    assert has_element?(view, "#home-note", "Home arrives later")
  end
end
