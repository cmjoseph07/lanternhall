defmodule LanternhallWeb.E2ECaseTest do
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright

  # An inline `style` attribute breaks `style-src 'self'`. Resolves once the browser has
  # reported the violation, which it does in a later task than the one that set the attribute.
  @break_csp """
  new Promise((resolve) => {
    document.addEventListener("securitypolicyviolation", () => resolve(true), { once: true });
    document.body.setAttribute("style", "color: red");
  })
  """

  test "assert_clean_browser fails on a CSP violation and names it", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_clean_browser()
      |> Playwright.evaluate(@break_csp)

    error = assert_raise ExUnit.AssertionError, fn -> assert_clean_browser(conn) end

    assert error.message == ~s(CSP violations: ["style-src-attr blocked inline"])
  end
end
