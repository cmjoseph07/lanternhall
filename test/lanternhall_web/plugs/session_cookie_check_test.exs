defmodule LanternhallWeb.Plugs.SessionCookieCheckTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias LanternhallWeb.RawHTTP

  @moduletag :capture_log

  @name "_lanternhall_test"
  @body "Bad Request: this browser holds more than one session cookie for this app. " <>
          "Clear its cookies for localhost, then open http://localhost:4002 again.\n"

  @websocket_upgrade [
    {"host", "localhost:4002"},
    {"origin", "http://localhost:4002"},
    {"upgrade", "websocket"},
    {"connection", "Upgrade"},
    {"sec-websocket-key", Base.encode64(:crypto.strong_rand_bytes(16))},
    {"sec-websocket-version", "13"}
  ]

  setup_all do
    page = get([])
    [set_cookie] = page.headers["set-cookie"]
    [session | _attributes] = String.split(set_cookie, ";")

    {:ok, session: session}
  end

  defp get(headers, path \\ "/fixtures/core") do
    RawHTTP.request("GET #{path} HTTP/1.1", [{"host", "localhost:4002"} | headers])
  end

  describe "a plain request" do
    test "with the session cookie once passes", %{session: session} do
      assert get([{"cookie", session}]).status == 200
    end

    # A cookie set by another localhost port with a longer path arrives first.
    test "with a second cookie of the session's name gets 400 with a plain body", ctx do
      response = get([{"cookie", "#{@name}=x; #{ctx.session}"}])

      assert response.status == 400
      assert response.headers["content-type"] == ["text/plain; charset=utf-8"]
      assert response.body == @body
    end

    for {shape, why} <- [
          {"<session>; <name>=x", "the stray cookie last"},
          {"<name>=x;<session>", "no space after the semicolon"},
          {"<name>=x;\t<session>", "a tab after the semicolon"},
          {"<name>=; <session>", "an empty value"},
          {"other=1; <name>=x; theme=dark; <session>", "other cookies in between"},
          {"<session>; <session>", "the same value twice"}
        ] do
      test "with the session cookie twice (#{why}) gets 400", %{session: session} do
        cookie =
          unquote(shape)
          |> String.replace("<name>", @name)
          |> String.replace("<session>", session)

        assert get([{"cookie", cookie}]).status == 400
      end
    end

    test "with the session cookie in two Cookie headers gets 400", %{session: session} do
      assert get([{"cookie", "#{@name}=x"}, {"cookie", session}]).status == 400
    end

    for {others, why} <- [
          {"other=1; other=2", "another cookie twice"},
          {"x#{@name}=1", "a name that ends with the session's"},
          {"#{@name}2=1", "a name that starts with the session's"},
          {"other=#{@name}=1", "the session's name inside a value"}
        ] do
      test "with the session cookie once and #{why} passes", %{session: session} do
        assert get([{"cookie", "#{unquote(others)}; #{session}"}]).status == 200
      end
    end

    for {path, kind} <- [
          {"/healthz", "the health check"},
          {"/robots.txt", "a static file"},
          {"/no-such-page", "a path with no route"}
        ] do
      test "for #{path} (#{kind}) with the session cookie twice gets 400", ctx do
        response = get([{"cookie", "#{@name}=x; #{ctx.session}"}], unquote(path))

        assert response.status == 400
        assert response.body == @body
      end
    end

    test "with the session cookie twice stops at the check and is logged", %{session: session} do
      {conn, log} =
        with_log(fn ->
          %{Phoenix.ConnTest.build_conn() | host: "localhost", port: 4002}
          |> Plug.Conn.put_req_header("cookie", "#{@name}=x; #{session}")
          |> Phoenix.ConnTest.dispatch(LanternhallWeb.Endpoint, :get, "/")
        end)

      assert conn.halted
      assert conn.status == 400
      assert conn.resp_body == @body
      assert log =~ "[warning] Refused a request that carried more than one session cookie"
    end

    test "refused for a second session cookie still carries the security headers", ctx do
      response = get([{"cookie", "#{@name}=x; #{ctx.session}"}])

      assert response.status == 400
      assert response.headers["x-content-type-options"] == ["nosniff"]
      assert [csp] = response.headers["content-security-policy"]
      assert csp =~ "default-src 'none'"
    end
  end

  describe "a LiveView WebSocket upgrade" do
    test "with the session cookie once is accepted", %{session: session} do
      response =
        RawHTTP.request(
          "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
          [{"cookie", session} | @websocket_upgrade]
        )

      assert response.status == 101
    end

    # The reported attack: a cookie with `Path=/live` reaches only the socket.
    test "with a second cookie of the session's name gets 400 with a plain body", ctx do
      response =
        RawHTTP.request(
          "GET /live/websocket?vsn=2.0.0 HTTP/1.1",
          [{"cookie", "#{@name}=x; #{ctx.session}"} | @websocket_upgrade]
        )

      assert response.status == 400
      assert response.body == @body
    end
  end
end
