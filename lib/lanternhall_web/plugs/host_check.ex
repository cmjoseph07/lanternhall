defmodule LanternhallWeb.Plugs.HostCheck do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @host "localhost"

  @impl Plug
  def call(conn, _opts) do
    endpoint = Phoenix.Controller.endpoint_module(conn)

    if conn.host == @host and conn.port == endpoint.config(:http)[:port] do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "Bad Request: open this app at #{endpoint.url()}\n")
      |> halt()
    end
  end
end
