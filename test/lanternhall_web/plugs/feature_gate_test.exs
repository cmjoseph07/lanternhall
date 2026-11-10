defmodule LanternhallWeb.Plugs.FeatureGateTest do
  # Real requests to the running test server (http://localhost:4002), so a gated route's
  # reply is compared with the reply for a URL that has no route, as the browser sees both.
  use ExUnit.Case, async: true

  alias LanternhallWeb.Plugs.FeatureGate
  alias LanternhallWeb.RawHTTP

  defp get(path, accept \\ "text/html") do
    RawHTTP.request("GET #{path} HTTP/1.1", [{"host", "localhost:4002"}, {"accept", accept}])
  end

  # No CSRF token: the gate must answer before the browser pipeline's forgery check.
  defp post(path) do
    RawHTTP.request("POST #{path} HTTP/1.1", [
      {"host", "localhost:4002"},
      {"accept", "text/html"},
      {"content-length", "0"}
    ])
  end

  # Header values such as the CSP nonce and request id differ per request; names must not.
  defp shape(response) do
    {response.status, response.headers["content-type"], Map.keys(response.headers), response.body}
  end

  test "an enabled feature's plain route responds" do
    response = get("/fixtures/core/plain")

    assert response.status == 200
    assert response.body == "fixture_core plain route"
  end

  test "a disabled feature's plain route answers exactly like a URL with no route" do
    disabled = get("/fixtures/personal/plain")

    assert disabled.status == 404
    assert shape(disabled) == shape(get("/no-such-page"))
  end

  # The gate runs before the browser pipeline, so its format negotiation and CSRF check
  # never get to answer 406 or 403 for a route that should not exist.
  test "a disabled feature's plain route answers like a URL with no route for any request" do
    assert shape(get("/fixtures/personal/plain", "application/json")) ==
             shape(get("/no-such-page", "application/json"))

    assert shape(get("/fixtures/personal/plain?_format=json")) ==
             shape(get("/no-such-page?_format=json"))

    assert shape(post("/fixtures/personal/plain")) == shape(post("/no-such-page"))
  end

  test "raises for an id no feature has, so a mistyped gate fails loudly" do
    conn = Plug.Test.conn(:get, "/")

    assert_raise ArgumentError, "no feature has id :fixture_typo", fn ->
      FeatureGate.call(conn, FeatureGate.init(:fixture_typo))
    end
  end
end
