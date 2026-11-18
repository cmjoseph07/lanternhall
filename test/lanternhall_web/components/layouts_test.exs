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

  describe "a flash" do
    # The fixture page puts one flash of each kind with `?flashes`.
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fixtures/core?flashes")

      %{view: view}
    end

    test "shows an info message in the info style", %{view: view} do
      assert has_element?(view, "#flash-info .alert-info:not(.alert-error)", "Fixture info flash")
    end

    test "shows an error message in the error style", %{view: view} do
      assert has_element?(
               view,
               "#flash-error .alert-error:not(.alert-info)",
               "Fixture error flash"
             )
    end
  end

  describe "the reconnect notices" do
    # Only the client shows them, when it loses the connection.
    for id <- ~w(client-error server-error) do
      test "##{id} starts hidden", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"/fixtures/core")

        assert has_element?(view, "##{unquote(id)}[hidden]")
      end
    end
  end
end
