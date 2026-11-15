defmodule LanternhallWeb.RawHTTPTest do
  # RawHTTP reads replies by hand, so its reader is checked against exact bytes on the
  # wire, served once by a socket in the test. The running test server's replies are
  # covered by every test that uses RawHTTP.
  use ExUnit.Case, async: true

  alias LanternhallWeb.RawHTTP

  @timeout 5_000

  # Serves `reply` to one request on a free loopback port and returns the port. The
  # connection then stays open until the client closes it, unless `:close` is asked for,
  # so a reader that waits for the end of the connection would time out.
  defp serve(reply, then \\ :wait) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    start_supervised!(
      Supervisor.child_spec(
        {Task,
         fn ->
           {:ok, socket} = :gen_tcp.accept(listener, @timeout)
           {:ok, _request} = :gen_tcp.recv(socket, 0, @timeout)
           :ok = :gen_tcp.send(socket, reply)
           if then == :wait, do: {:error, :closed} = :gen_tcp.recv(socket, 0, @timeout)
           :gen_tcp.close(socket)
         end},
        id: {:canned_server, port}
      )
    )

    port
  end

  defp get(reply, then \\ :wait) do
    RawHTTP.request("GET / HTTP/1.1", [{"host", "localhost"}], "", port: serve(reply, then))
  end

  test "keeps every value of a repeated header, in the order sent" do
    response =
      get("""
      HTTP/1.1 200 OK\r
      Set-Cookie: a=1; path=/\r
      Content-Length: 2\r
      Set-Cookie: b=2; path=/\r
      \r
      ok\
      """)

    assert response.status == 200
    assert response.headers["set-cookie"] == ["a=1; path=/", "b=2; path=/"]
    assert response.headers["content-length"] == ["2"]
    assert response.body == "ok"
  end

  test "reads a chunked body, skipping chunk extensions and trailers" do
    response =
      get("""
      HTTP/1.1 200 OK\r
      Transfer-Encoding: chunked\r
      \r
      5\r
      hello\r
      7;note=1\r
      , world\r
      0\r
      X-Trailer: 1\r
      \r
      """)

    assert response.body == "hello, world"
  end

  test "reads to the end of the connection when the reply gives no length" do
    response = get("HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n\r\nuntil the end", :close)

    assert response.headers["content-type"] == ["text/plain"]
    assert response.body == "until the end"
  end

  test "reads an empty body when the length is 0" do
    assert get("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n").body == ""
  end

  test "reads no body for a reply that cannot have one" do
    # 304 and a reply to HEAD may carry the length the body would have had.
    assert get("HTTP/1.1 204 No Content\r\n\r\n").body == ""
    assert get("HTTP/1.1 304 Not Modified\r\nContent-Length: 5\r\n\r\n").body == ""

    port = serve("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n")
    head = RawHTTP.request("HEAD / HTTP/1.1", [{"host", "localhost"}], "", port: port)
    assert head.status == 200
    assert head.body == ""
  end
end
