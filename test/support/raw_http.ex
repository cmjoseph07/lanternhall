defmodule LanternhallWeb.RawHTTP do
  @moduledoc """
  Sends one hand-written HTTP/1.x request to the running test server and reads the reply.

  HTTP clients always send a correct `Host` header; the Host, Origin and WebSocket
  upgrade tests need to send a wrong one, or none at all, exactly as an attacker would.
  """

  @timeout 5_000

  @doc """
  Sends `request_line` (for example `"GET / HTTP/1.1"`) with `headers` and `body`, and
  returns the response status, headers (names lowercased) and body. The caller sets any
  `content-length` the body needs.

  A `101 Switching Protocols` reply is returned without reading further, so a
  successful WebSocket upgrade does not block the test.
  """
  def request(request_line, headers, body \\ "") do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, LanternhallWeb.Endpoint.config(:http)[:port], [
        :binary,
        active: false,
        packet: :http_bin
      ])

    try do
      head = [request_line, "\r\n", Enum.map(headers, fn {k, v} -> [k, ": ", v, "\r\n"] end)]
      :ok = :gen_tcp.send(socket, [head, "\r\n", body])

      {:ok, {:http_response, _version, status, _reason}} = :gen_tcp.recv(socket, 0, @timeout)
      resp_headers = recv_headers(socket, %{})
      :ok = :inet.setopts(socket, packet: :raw)

      %{status: status, headers: resp_headers, body: recv_body(socket, status, resp_headers)}
    after
      :gen_tcp.close(socket)
    end
  end

  defp recv_headers(socket, acc) do
    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, {:http_header, _, name, _, value}} ->
        recv_headers(socket, Map.put(acc, name |> to_string() |> String.downcase(), value))

      {:ok, :http_eoh} ->
        acc
    end
  end

  defp recv_body(_socket, 101, _headers), do: ""

  # Bandit sends a Content-Length on every reply these tests get.
  defp recv_body(socket, _status, %{"content-length" => length}) do
    case String.to_integer(length) do
      0 ->
        ""

      length ->
        {:ok, body} = :gen_tcp.recv(socket, length, @timeout)
        body
    end
  end
end
