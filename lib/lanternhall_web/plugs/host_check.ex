defmodule LanternhallWeb.Plugs.HostCheck do
  @moduledoc """
  Rejects every request whose `Host` is not the endpoint's own `localhost:<port>`
  with `400` and a plain body (SPEC-platform.md section 3.3).

  The app listens on loopback only, but a web page can still reach it through DNS
  rebinding: the page's own name first resolves to the attacker's server, then to
  `127.0.0.1`, and the browser keeps sending that name as `Host`. Only requests for
  `localhost:<port>` get through.

  `LanternhallWeb.Endpoint.call/2` runs this before Phoenix dispatches sockets, so
  LiveView WebSocket upgrades are checked too.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    endpoint = Phoenix.Controller.endpoint_module(conn)
    %URI{host: host, port: port} = endpoint.struct_url()

    if conn.host == host and conn.port == port do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "Bad Request: open this app at #{endpoint.url()}\n")
      |> halt()
    end
  end
end
