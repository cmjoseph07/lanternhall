defmodule LanternhallWeb.RawHTTP do
  @moduledoc """
  Sends one hand-written HTTP/1.x request to the running test server and reads the reply.

  HTTP clients always send a correct `Host` header; the Host, Origin and WebSocket
  upgrade tests need to send a wrong one, or none at all, exactly as an attacker would.
  """

  @timeout 5_000

  @doc """
  Sends `request_line` (for example `"GET / HTTP/1.1"`) with `headers` and `body`, and
  returns the response status, headers and body. The caller sets any `content-length`
  the body needs.

  The response headers are a map of lowercased name to the list of that header's
  values, in the order sent, so a header sent more than once (`set-cookie`) keeps every
  value.

  The body is read the way the reply frames it: chunked, by `content-length`, or to the
  end of the connection. A reply that cannot have a body (1xx, 204, 304, or any reply
  to `HEAD`) is returned without reading further, so a successful WebSocket upgrade
  (`101 Switching Protocols`) does not block the test.

  `opts[:port]` sends the request to another loopback port than the test server's.
  """
  def request(request_line, headers, body \\ "", opts \\ []) do
    port = Keyword.get_lazy(opts, :port, fn -> LanternhallWeb.Endpoint.config(:http)[:port] end)

    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :http_bin])

    try do
      head = [request_line, "\r\n", Enum.map(headers, fn {k, v} -> [k, ": ", v, "\r\n"] end)]
      :ok = :gen_tcp.send(socket, [head, "\r\n", body])

      {:ok, {:http_response, _version, status, _reason}} = :gen_tcp.recv(socket, 0, @timeout)
      resp_headers = recv_headers(socket, %{})

      resp_body =
        if bodiless?(request_line, status), do: "", else: recv_body(socket, resp_headers)

      %{status: status, headers: resp_headers, body: resp_body}
    after
      :gen_tcp.close(socket)
    end
  end

  defp recv_headers(socket, acc) do
    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, {:http_header, _, name, _, value}} ->
        name = name |> to_string() |> String.downcase()
        recv_headers(socket, Map.update(acc, name, [value], &(&1 ++ [value])))

      {:ok, :http_eoh} ->
        acc
    end
  end

  # https://www.rfc-editor.org/rfc/rfc9112#section-6.3
  defp bodiless?(request_line, status) do
    String.starts_with?(request_line, "HEAD ") or status < 200 or status in [204, 304]
  end

  defp recv_body(socket, headers) do
    cond do
      chunked?(headers) -> recv_chunks(socket, [])
      length = headers["content-length"] -> recv_exactly(socket, String.to_integer(hd(length)))
      true -> recv_until_closed(socket, [])
    end
  end

  defp chunked?(headers) do
    headers
    |> Map.get("transfer-encoding", [])
    |> Enum.any?(&(String.downcase(&1) =~ "chunked"))
  end

  # Each chunk is its size in hex on a line of its own (a ";" starts extensions, which
  # are skipped), then that many bytes and a line end. Size 0 ends the body; trailer
  # lines may follow it, up to an empty line.
  defp recv_chunks(socket, acc) do
    case socket |> recv_line() |> String.split(";") |> hd() |> String.to_integer(16) do
      0 ->
        skip_trailers(socket)
        IO.iodata_to_binary(acc)

      size ->
        chunk = recv_exactly(socket, size)
        "" = recv_line(socket)
        recv_chunks(socket, [acc, chunk])
    end
  end

  defp skip_trailers(socket) do
    if recv_line(socket) != "", do: skip_trailers(socket)
  end

  defp recv_line(socket) do
    :ok = :inet.setopts(socket, packet: :line)
    {:ok, line} = :gen_tcp.recv(socket, 0, @timeout)
    String.trim_trailing(line, "\r\n")
  end

  # A length of 0 would ask :gen_tcp.recv/3 for whatever arrives next, and wait for it.
  defp recv_exactly(_socket, 0), do: ""

  defp recv_exactly(socket, length) do
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, bytes} = :gen_tcp.recv(socket, length, @timeout)
    bytes
  end

  defp recv_until_closed(socket, acc) do
    :ok = :inet.setopts(socket, packet: :raw)

    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, bytes} -> recv_until_closed(socket, [acc, bytes])
      {:error, :closed} -> IO.iodata_to_binary(acc)
    end
  end
end
