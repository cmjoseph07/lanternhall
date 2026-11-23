defmodule LanternhallWeb.E2ECaseTest do
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright

  @csp_report "Applying inline style violates the following Content Security Policy directive " <>
                "'style-src 'self''. Either the 'unsafe-inline' keyword, a hash " <>
                "('sha256-NerDAUWfwD31YdZHveMrq0GLjsNFMwxLpZl0dPUeCcw='), or a nonce ('nonce-...') " <>
                "is required to enable inline execution. Note that hashes do not apply to event " <>
                "handlers, style attributes and javascript: navigations unless the " <>
                "'unsafe-hashes' keyword is present. The action has been blocked."

  # An inline `style` attribute breaks `style-src 'self'`. Resolves once the browser has
  # reported the violation, which it does in a later task than the one that set the attribute.
  @break_csp """
  new Promise((resolve) => {
    document.addEventListener("securitypolicyviolation", () => resolve(true), { once: true });
    document.body.setAttribute("style", "color: red");
  })
  """

  @moduletag :capture_log

  @tag browser_errors: ["boom"]
  test "a browser error the test does not expect fails the assertion", %{
    conn: conn,
    browser_watcher: watcher
  } do
    conn = conn |> visit(~p"/") |> assert_has("[data-phx-main].phx-connected")

    assert_raise ExUnit.AssertionError, fn -> assert_browser_errors(watcher, ~r/boom/) end

    Playwright.evaluate(conn, ~s|console.error("boom")|)

    assert_raise ExUnit.AssertionError, fn -> assert_browser_errors(watcher, []) end
    assert_raise ExUnit.AssertionError, fn -> assert_browser_errors(watcher, ~r/bang/) end
  end

  @tag browser_errors: ["boom in the second tab"]
  test "a console error in a second tab is a browser error", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")

    conn
    |> open_tab()
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(~s|console.error("boom in the second tab")|)
  end

  @tag browser_errors: ["Error: thrown in the second tab"]
  test "an uncaught error in a second tab is a browser error", %{conn: conn} do
    conn
    |> open_tab()
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate("""
    new Promise((resolve) => {
      window.addEventListener("error", () => resolve(true), { once: true });
      setTimeout(() => { throw new Error("thrown in the second tab"); });
    })
    """)
  end

  @tag browser_errors: [@csp_report]
  test "a CSP violation on a page the test has left is a browser error", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(@break_csp)
    |> visit(~p"/settings")
    |> assert_has("[data-phx-main].phx-connected")
  end
end
