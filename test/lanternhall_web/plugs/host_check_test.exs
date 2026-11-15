defmodule LanternhallWeb.Plugs.HostCheckTest do
  # Real requests to the running test server (http://localhost:4002), so Bandit parses
  # the Host header and Phoenix dispatches sockets exactly as for the browser. One test
  # dispatches through the endpoint in the test process instead, to see the conn.
  use ExUnit.Case, async: true

  # Bandit logs every request it rejects itself (no Host on HTTP/1.1).
  @moduletag :capture_log

  alias LanternhallWeb.RawHTTP

  @websocket_upgrade [
    {"upgrade", "websocket"},
    {"connection", "Upgrade"},
    {"sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16))},
    {"sec-websocket-version", "13"}
  ]

  @bad_hosts [
    {"127.0.0.1:4002", "the loopback address instead of localhost"},
    {"evil.test", "a foreign name, as in DNS rebinding"},
    {"evil.test:4002", "a foreign name with the app's port"},
    {"localhost:4000", "the wrong port"},
    {"localhost", "no port"}
  ]

  describe "a plain request" do
    test "with Host localhost:4002 passes" do
      response = RawHTTP.request("GET /healthz HTTP/1.1", [{"host", "localhost:4002"}])

      assert response.status == 200
    end

    for {host, why} <- @bad_hosts do
      test "with Host #{host} (#{why}) gets 400 with a plain body" do
        response = RawHTTP.request("GET / HTTP/1.1", [{"host", unquote(host)}])

        assert response.status == 400
        assert response.headers["content-type"] == ["text/plain; charset=utf-8"]
        assert response.body == "Bad Request: open this app at http://localhost:4002\n"
      end
    end

    test "without a Host header (HTTP/1.0) gets 400 with a plain body" do
      response = RawHTTP.request("GET / HTTP/1.0", [])

      assert response.status == 400
      assert response.headers["content-type"] == ["text/plain; charset=utf-8"]
      assert response.body == "Bad Request: open this app at http://localhost:4002\n"
    end

    # HTTP/1.1 requires Host, so Bandit refuses the request before the app sees it.
    test "without a Host header (HTTP/1.1) gets 400 with an empty body" do
      response = RawHTTP.request("GET / HTTP/1.1", [])

      assert response.status == 400
      assert response.body == ""
    end

    # Every kind of route sits behind the check, not only the pages.
    for {path, kind} <- [
          {"/healthz", "the health check"},
          {"/robots.txt", "a static file"},
          {"/images/logo.svg", "a static file in a directory"},
          {"/no-such-page", "a path with no route"},
          {"/fixtures/core/plain", "a feature's route"}
        ] do
      test "for #{path} (#{kind}) with a bad Host gets 400 with a plain body" do
        response = RawHTTP.request("GET #{unquote(path)} HTTP/1.1", [{"host", "evil.test"}])

        assert response.status == 400
        assert response.headers["content-type"] == ["text/plain; charset=utf-8"]
        assert response.body == "Bad Request: open this app at http://localhost:4002\n"
      end
    end

    # The 400 alone does not prove this: without the halt the client gets the same
    # reply, and the endpoint's plugs then run on the rejected request and raise
    # `Plug.Conn.AlreadySentError` in the server. Dispatched in the test process, the
    # same endpoint hands back the conn, or the error.
    test "with a bad Host stops at the check" do
      conn =
        Phoenix.ConnTest.dispatch(
          %{Phoenix.ConnTest.build_conn() | host: "evil.test"},
          LanternhallWeb.Endpoint,
          :get,
          "/"
        )

      assert conn.halted
      assert conn.status == 400
    end

    test "rejected with a bad Host still carries the security headers" do
      response = RawHTTP.request("GET / HTTP/1.1", [{"host", "evil.test"}])

      assert response.status == 400
      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert [csp] = response.headers["content-security-policy"]
      assert csp =~ "default-src 'none'"
    end
  end

  describe "a LiveView WebSocket upgrade" do
    test "with Host localhost:4002 is accepted" do
      response =
        RawHTTP.request(
          "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
          [{"host", "localhost:4002"}, {"origin", "http://localhost:4002"} | @websocket_upgrade]
        )

      assert response.status == 101
    end

    for {host, why} <- @bad_hosts do
      test "with Host #{host} (#{why}) gets 400 with a plain body" do
        response =
          RawHTTP.request(
            "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
            [{"host", unquote(host)}, {"origin", "http://localhost:4002"} | @websocket_upgrade]
          )

        assert response.status == 400
        assert response.body == "Bad Request: open this app at http://localhost:4002\n"
      end
    end

    test "without a Host header gets 400 with an empty body" do
      response =
        RawHTTP.request(
          "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
          [{"origin", "http://localhost:4002"} | @websocket_upgrade]
        )

      assert response.status == 400
      assert response.body == ""
    end
  end
end
