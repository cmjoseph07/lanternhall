defmodule LanternhallWeb.SecurityTest do
  # Origin and CSRF checks (SPEC-platform.md section 3.3).
  use LanternhallWeb.ConnCase, async: true

  # Phoenix logs every refused Origin; keep the expected noise out of the test output.
  @moduletag :capture_log

  alias LanternhallWeb.RawHTTP

  @websocket_upgrade [
    {"host", "localhost:4002"},
    {"upgrade", "websocket"},
    {"connection", "Upgrade"},
    {"sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16))},
    {"sec-websocket-version", "13"}
  ]

  describe "LiveView socket connect" do
    test "from Origin http://localhost:4002 is accepted" do
      response =
        RawHTTP.request(
          "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
          [{"origin", "http://localhost:4002"} | @websocket_upgrade]
        )

      assert response.status == 101
    end

    for origin <- ["http://evil.test", "http://127.0.0.1:4002", "http://localhost:4000"] do
      test "from Origin #{origin} is refused" do
        response =
          RawHTTP.request(
            "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
            [{"origin", unquote(origin)} | @websocket_upgrade]
          )

        assert response.status == 403
      end
    end
  end

  describe "a POST through the :browser pipeline" do
    # No browser route takes a POST yet, so these tests run the pipeline that every
    # browser route goes through. Phoenix.ConnTest skips CSRF checks unless told not to.
    test "without a CSRF token is refused with 403" do
      # Pipeline plugs wrap what they raise; the endpoint unwraps it into the response.
      %Plug.Conn.WrapperError{reason: error} =
        assert_raise Plug.Conn.WrapperError, fn ->
          :post
          |> build_conn("/", %{})
          |> init_test_session(%{})
          |> put_private(:plug_skip_csrf_protection, false)
          |> LanternhallWeb.Router.browser([])
        end

      assert %Plug.CSRFProtection.InvalidCSRFTokenError{} = error
      assert Plug.Exception.status(error) == 403
    end

    test "with a valid CSRF token passes" do
      token = Plug.CSRFProtection.get_csrf_token()

      conn =
        :post
        |> build_conn("/", %{"_csrf_token" => token})
        |> init_test_session(%{"_csrf_token" => Plug.CSRFProtection.dump_state()})
        |> put_private(:plug_skip_csrf_protection, false)
        |> LanternhallWeb.Router.browser([])

      refute conn.halted
    end
  end
end
