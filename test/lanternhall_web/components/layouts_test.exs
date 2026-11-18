defmodule LanternhallWeb.LayoutsTest do
  use LanternhallWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @theme_js Path.expand("../../../assets/js/theme.js", __DIR__)

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

  describe "the theme script" do
    # Biome checks the file, so the page must run the file and nothing else inline.
    test "is assets/js/theme.js as written", %{conn: conn} do
      inline =
        conn
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("script:not([src])")
        |> LazyHTML.text()

      assert String.trim(inline) == String.trim(File.read!(@theme_js))
    end
  end
end
