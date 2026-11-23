defmodule LanternhallWeb.Plugs.SessionCookieCheck do
  @moduledoc """
  Browsers send a host's cookies to every port on it, and let a page from any of those
  ports set them. A page on another localhost port can therefore add a second cookie of
  the session's name, for example with `Path=/live`. The browser sends the cookie with
  the longer path first and Plug reads the first, so the LiveView socket would open
  without a session, LiveView would refuse the join, and the page would reload without
  end.

  The `__Host-` name prefix would have the browser refuse the stray cookie itself, but
  it needs a `Secure` cookie, and Safari takes none from `http://localhost`.
  """
  @behaviour Plug

  import Plug.Conn

  require Logger

  @doc """
  Takes the session cookie's name as `key:`, the same one `Plug.Session` is given.
  """
  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :key) <> "="

  @impl Plug
  def call(conn, name_and_equals) do
    if session_cookies(conn, name_and_equals) > 1 do
      endpoint = Phoenix.Controller.endpoint_module(conn)

      Logger.warning(
        "Refused a request that carried more than one session cookie. " <>
          "Clear the browser's cookies for localhost."
      )

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(
        400,
        "Bad Request: this browser holds more than one session cookie for this app. " <>
          "Clear its cookies for localhost, then open #{endpoint.url()} again.\n"
      )
      |> halt()
    else
      conn
    end
  end

  # Counts as `Plug.Conn.Cookies.decode/1` reads them: pairs split on `;`, the name
  # running up to the first `=`. Plug skips only spaces and tabs before a name; trimming
  # all leading whitespace here can count a pair Plug would drop, never miss one it reads.
  defp session_cookies(conn, name_and_equals) do
    conn
    |> get_req_header("cookie")
    |> Enum.flat_map(&String.split(&1, ";"))
    |> Enum.count(&(&1 |> String.trim_leading() |> String.starts_with?(name_and_equals)))
  end
end
