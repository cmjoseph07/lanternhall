defmodule LanternhallWeb.E2E.Platform.SessionCookieTest do
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright
  alias PlaywrightEx.BrowserContext

  @reconnect """
  new Promise((resolve) => {
    const socket = window.liveSocket.socket;
    socket.onOpen(() => resolve("open"));
    socket.onError(() => resolve("refused"));
    window.liveSocket.disconnect();
    window.liveSocket.connect();
  })
  """

  # Any page on another localhost port can set this cookie. The browser sends it to
  # /live ahead of the real one; before the check, the socket then opened without a
  # session, LiveView refused the join and the page reloaded without end. A value set
  # on `window` lives as long as the document, so it is gone after a reload.
  @tag :capture_log
  test "a second session cookie with Path=/live stops the socket, and the page stays",
       %{conn: conn} do
    conn =
      conn
      |> visit(~p"/fixtures/core")
      |> assert_has("[data-phx-main].phx-connected")
      |> Playwright.evaluate("window.__doc = 1")

    {:ok, _} =
      BrowserContext.add_cookies(conn.context_id,
        cookies: [%{name: "_lanternhall_test", value: "x", domain: "localhost", path: "/live"}],
        timeout: Playwright.Config.global(:timeout)
      )

    conn
    |> Playwright.evaluate(@reconnect, &assert(&1 == "refused"))
    |> assert_has("#client-error")
    |> Playwright.evaluate("window.__doc", &assert(&1 == 1))
  end
end
