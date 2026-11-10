defmodule LanternhallWeb.SecurityTest do
  # Origin and CSRF checks (SPEC-platform.md section 3.3).
  use ExUnit.Case, async: true

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

    # WebSocket is the only transport: on loopback the long-poll fallback is never
    # needed, and a transport that does not exist cannot be reached from another Origin.
    test "over long-poll is not offered" do
      response =
        RawHTTP.request("GET /live/longpoll?vsn=2.0.0 HTTP/1.1", [
          {"host", "localhost:4002"},
          {"origin", "http://localhost:4002"}
        ])

      assert response.status == 404
    end
  end

  describe "the session cookie" do
    setup do
      response =
        RawHTTP.request("GET /fixtures/core HTTP/1.1", [
          {"host", "localhost:4002"},
          {"accept", "text/html"}
        ])

      assert response.status == 200
      {:ok, cookie: response.headers["set-cookie"]}
    end

    test "is named for this env, so other envs on the machine leave it alone", %{cookie: cookie} do
      assert cookie =~ ~r/^_lanternhall_test=/
    end

    # Strict would drop the cookie when a link on another site opens the app, which
    # starts a new session and breaks the CSRF token of every tab already open.
    test "is SameSite=Lax, not Strict", %{cookie: cookie} do
      assert cookie =~ ~r/; SameSite=Lax(;|$)/
    end
  end

  describe "a form POST through the :browser pipeline" do
    # Real requests to the fixture route POST /fixtures/core/plain, which pipes through
    # :browser like every browser route, carrying what a browser holds after loading a
    # page: the session cookie and the page's CSRF token.
    setup do
      page =
        RawHTTP.request("GET /fixtures/core HTTP/1.1", [
          {"host", "localhost:4002"},
          {"accept", "text/html"}
        ])

      [cookie | _attributes] = String.split(page.headers["set-cookie"], ";")

      [token] =
        page.body
        |> LazyHTML.from_document()
        |> LazyHTML.query("meta[name=csrf-token]")
        |> LazyHTML.attribute("content")

      {:ok, cookie: cookie, token: token}
    end

    defp post_plain(headers, body) do
      RawHTTP.request(
        "POST /fixtures/core/plain HTTP/1.1",
        [
          {"host", "localhost:4002"},
          {"accept", "text/html"},
          {"content-type", "application/x-www-form-urlencoded"},
          {"content-length", Integer.to_string(byte_size(body))} | headers
        ],
        body
      )
    end

    test "with the page's token and session cookie is let through", ctx do
      body = URI.encode_query(%{"_csrf_token" => ctx.token})
      response = post_plain([{"cookie", ctx.cookie}], body)

      assert response.status == 200
      assert response.body == "fixture_core plain post"
    end

    test "without a token is refused with 403", %{cookie: cookie} do
      assert post_plain([{"cookie", cookie}], "").status == 403
    end

    test "with a token but no session cookie is refused with 403", %{token: token} do
      assert post_plain([], URI.encode_query(%{"_csrf_token" => token})).status == 403
    end
  end
end
