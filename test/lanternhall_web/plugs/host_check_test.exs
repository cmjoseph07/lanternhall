defmodule LanternhallWeb.Plugs.HostCheckTest do
  # Real requests to the running test server (http://localhost:4002), so Bandit parses
  # the Host header and Phoenix dispatches sockets exactly as for the browser.
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
        assert response.headers["content-type"] == "text/plain; charset=utf-8"
        assert response.body == "Bad Request: open this app at http://localhost:4002\n"
      end
    end

    test "without a Host header (HTTP/1.0) gets 400 with a plain body" do
      response = RawHTTP.request("GET / HTTP/1.0", [])

      assert response.status == 400
      assert response.headers["content-type"] == "text/plain; charset=utf-8"
      assert response.body == "Bad Request: open this app at http://localhost:4002\n"
    end

    # HTTP/1.1 requires Host, so Bandit refuses the request before the app sees it.
    test "without a Host header (HTTP/1.1) gets 400 with an empty body" do
      response = RawHTTP.request("GET / HTTP/1.1", [])

      assert response.status == 400
      assert response.body == ""
    end

    test "rejected with a bad Host still carries the security headers" do
      response = RawHTTP.request("GET / HTTP/1.1", [{"host", "evil.test"}])

      assert response.status == 400
      assert response.headers["x-content-type-options"] == "nosniff"
      assert response.headers["content-security-policy"] =~ "default-src 'none'"
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
