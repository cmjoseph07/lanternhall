defmodule LanternhallWeb.FeatureGateTest do
  use LanternhallWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LanternhallWeb.{DisabledFeatureError, FeatureGate, RawHTTP}

  defp raw_get(path) do
    RawHTTP.request("GET #{path} HTTP/1.1", [{"host", "localhost:4002"}, {"accept", "text/html"}])
  end

  # Header values such as the CSP nonce and request id differ per request; names must not.
  defp shape(response) do
    {response.status, response.headers["content-type"], Map.keys(response.headers), response.body}
  end

  test "an enabled feature's LiveView mounts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/fixtures/core")

    assert has_element?(view, "#fixture-core")
  end

  test "a disabled feature's LiveView answers exactly like a URL with no route" do
    # Real requests to the running test server, as the browser sends them.
    disabled = raw_get("/fixtures/personal")

    assert disabled.status == 404
    assert shape(disabled) == shape(raw_get("/no-such-page"))
  end

  test "live navigation into a disabled feature's LiveView ends in the 404 reply", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/fixtures/core")

    redirect = view |> element("#to-fixture-personal") |> render_click()

    assert {:error, {:live_redirect, %{to: "/fixtures/personal"}}} = redirect

    assert {404, _headers, "Not Found"} =
             assert_error_sent(404, fn -> follow_redirect(redirect, conn) end)
  end

  describe "on_mount/4" do
    test "continues for an enabled feature" do
      socket = %Phoenix.LiveView.Socket{}

      assert FeatureGate.on_mount(:fixture_core, %{}, %{}, socket) == {:cont, socket}
    end

    # A connected mount that raises an exception with a 4xx status makes the LiveView
    # client reload the page, whose HTTP render then raises again and answers 404. This
    # happens when an open window reconnects after a restart that disabled the feature.
    test "raises a 404 error for a disabled feature" do
      error =
        assert_raise DisabledFeatureError,
                     "feature :fixture_personal is disabled on this install",
                     fn ->
                       FeatureGate.on_mount(
                         :fixture_personal,
                         %{},
                         %{},
                         %Phoenix.LiveView.Socket{}
                       )
                     end

      assert Plug.Exception.status(error) == 404
    end
  end
end
