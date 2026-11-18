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
      assert [cookie] = response.headers["set-cookie"]
      {:ok, cookie: cookie}
    end

    test "is named for this env, so other envs on the machine leave it alone", %{cookie: cookie} do
      assert cookie =~ ~r/^_lanternhall_test=/
    end

    # The session holds the CSRF token; no script on a page needs to read it, so none can.
    test "is HttpOnly", %{cookie: cookie} do
      assert cookie =~ ~r/; HttpOnly(;|$)/
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

      [set_cookie] = page.headers["set-cookie"]
      [cookie | _attributes] = String.split(set_cookie, ";")

      [token] =
        page.body
        |> LazyHTML.from_document()
        |> LazyHTML.query("meta[name=csrf-token]")
        |> LazyHTML.attribute("content")

      {:ok, cookie: cookie, token: token}
    end

    defp post_plain(headers, body, content_type \\ "application/x-www-form-urlencoded") do
      RawHTTP.request(
        "POST /fixtures/core/plain HTTP/1.1",
        [
          {"host", "localhost:4002"},
          {"accept", "text/html"},
          {"content-type", content_type},
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

    # No page uploads a file, so the endpoint parses no multipart body. Any site can send
    # one to this port without a preflight, and it would be parsed ahead of this check
    # and of the router; unparsed, its token is never seen.
    test "as a multipart body is refused with 403, its token unread", ctx do
      body =
        "--b\r\ncontent-disposition: form-data; name=\"_csrf_token\"\r\n\r\n" <>
          ctx.token <> "\r\n--b--\r\n"

      response = post_plain([{"cookie", ctx.cookie}], body, "multipart/form-data; boundary=b")

      assert response.status == 403
    end
  end
end
