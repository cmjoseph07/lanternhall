defmodule LanternhallWeb.StaticReloadTest do
  use LanternhallWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  setup context do
    put_static_manifest(context, %{"assets/js/app.js" => "assets/js/app-latest.js"})
  end

  defp mount(conn, path, tracked) do
    conn
    |> put_connect_params(%{"_track_static" => ["#{@endpoint.url()}/assets/js/#{tracked}?vsn=d"]})
    |> live(path)
  end

  test "a page holding a replaced static file is sent to its own URL again", %{conn: conn} do
    assert mount(conn, "/settings?tab=about", "app-replaced.js") ==
             {:error, {:redirect, %{to: "/settings?tab=about", status: 302}}}

    assert {:error, {:redirect, %{to: "/fixtures/core"}}} =
             mount(conn, "/fixtures/core", "app-replaced.js")
  end

  test "a page holding the latest static files mounts", %{conn: conn} do
    assert {:ok, view, _html} = mount(conn, "/settings?tab=about", "app-latest.js")

    assert has_element?(view, "#install")
  end
end
