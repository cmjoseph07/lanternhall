defmodule LanternhallWeb.Plugs.SecurityHeadersTest do
  use LanternhallWeb.ConnCase

  alias LanternhallWeb.Plugs.SecurityHeaders

  # SPEC-platform.md section 3.3, character for character; only the nonce varies.
  @csp ~r/\Adefault-src 'none'; script-src 'self' 'nonce-(?<nonce>[A-Za-z0-9+\/]{22}==)'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'\z/

  @other_headers %{
    "x-content-type-options" => "nosniff",
    "referrer-policy" => "no-referrer",
    "cross-origin-resource-policy" => "same-origin",
    "permissions-policy" => "camera=(), microphone=(), geolocation=()"
  }

  describe "HTML response" do
    test "carries the exact headers and a nonce matching the inline theme script", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert html_response(conn, 200)
      nonce = assert_security_headers(conn)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      scripts =
        conn.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("script:not([src])")

      assert Enum.count(scripts) == 1
      assert LazyHTML.attribute(scripts, "nonce") == [nonce]
    end

    test "gets a fresh nonce on every request", %{conn: conn} do
      first = conn |> get(~p"/") |> assert_security_headers()
      second = build_conn() |> get(~p"/") |> assert_security_headers()

      refute first == second
    end
  end

  describe "static response" do
    test "a digested request is cached for a year, immutable", %{conn: conn} do
      conn = get(conn, "/robots.txt?vsn=d")

      assert response(conn, 200)
      assert_security_headers(conn)
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "a non-digested request is revalidated by etag", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert response(conn, 200)
      assert_security_headers(conn)
      assert get_resp_header(conn, "cache-control") == ["public"]
      assert [_etag] = get_resp_header(conn, "etag")
    end
  end

  describe "/healthz response" do
    test "carries the exact headers and is never stored", %{conn: conn} do
      conn = get(conn, ~p"/healthz")

      assert json_response(conn, 200)
      assert_security_headers(conn)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "error response" do
    test "keeps the strict policy outside dev", %{conn: conn} do
      conn = conn |> SecurityHeaders.call(SecurityHeaders.init([])) |> send_resp(500, "")

      assert_security_headers(conn)
    end
  end

  describe "dev tools carve-out (dev only, SPEC-platform.md section 3.3)" do
    setup do
      %{opts: SecurityHeaders.init(dev_tools: true)}
    end

    # 399 is the highest status below an error, so it pins the boundary.
    for status <- [200, 302, 399] do
      test "a #{status} page also allows the live-reload frame", %{conn: conn, opts: opts} do
        conn = conn |> SecurityHeaders.call(opts) |> send_resp(unquote(status), "")

        [csp] = get_resp_header(conn, "content-security-policy")
        assert csp =~ ~r/; frame-ancestors 'none'; frame-src 'self'\z/
        assert String.replace(csp, "; frame-src 'self'", "") =~ @csp
      end
    end

    for path <- ["/phoenix/live_reload/frame", "/dev/dashboard/home"] do
      test "#{path} has no CSP but every other header", %{opts: opts} do
        conn = :get |> build_conn(unquote(path)) |> SecurityHeaders.call(opts)

        assert get_resp_header(conn, "content-security-policy") == []
        assert_other_headers(conn)
      end
    end

    # 400 is the lowest error status, so it pins the boundary.
    for status <- [400, 404, 500] do
      test "a #{status} error page drops the CSP for the debugger", %{conn: conn, opts: opts} do
        conn = conn |> SecurityHeaders.call(opts) |> send_resp(unquote(status), "")

        assert get_resp_header(conn, "content-security-policy") == []
        assert_other_headers(conn)
      end
    end
  end

  defp assert_security_headers(conn) do
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert %{"nonce" => nonce} = Regex.named_captures(@csp, csp)
    assert conn.assigns.csp_nonce == nonce
    assert_other_headers(conn)
    assert get_resp_header(conn, "cross-origin-opener-policy") == []
    assert get_resp_header(conn, "cross-origin-embedder-policy") == []
    nonce
  end

  defp assert_other_headers(conn) do
    for {name, value} <- @other_headers do
      assert get_resp_header(conn, name) == [value], "#{name}"
    end
  end
end
