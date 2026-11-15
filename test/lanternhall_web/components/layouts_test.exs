defmodule LanternhallWeb.LayoutsTest do
  use LanternhallWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "the page title" do
    # The fixture page sets no title of its own.
    test "is the app name alone on a page that sets none", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fixtures/core")

      assert page_title(view) == "Lanternhall"
    end
  end
end
