defmodule LanternhallWeb.E2ECase do
  @moduledoc """
  Real-browser test case: `PhoenixTest.Playwright.Case` in headless Chromium
  against the test server at http://localhost:4002, tagged `:e2e`.

  Each test's browser page is watched from its first request: console errors,
  uncaught page errors and Content-Security-Policy violations are collected,
  and `assert_clean_browser/1` fails the test if any happened.
  """
  use ExUnit.CaseTemplate

  alias PhoenixTest.Playwright
  alias PlaywrightEx.BrowserContext

  # Runs in the page before any of its own scripts, outside the page's CSP.
  @record_csp_violations """
  window.__cspViolations = [];
  document.addEventListener("securitypolicyviolation", (e) => {
    window.__cspViolations.push(`${e.effectiveDirective} blocked ${e.blockedURI || "inline"}`);
  });
  """

  using do
    quote do
      # Not async: the SQLite sandbox cannot share a database across concurrent tests.
      use PhoenixTest.Playwright.Case, async: false
      use LanternhallWeb, :verified_routes

      import LanternhallWeb.E2ECase

      @moduletag :e2e

      setup :watch_browser
    end
  end

  @doc """
  Subscribes the test process to the page's console and page error events and
  records CSP violations in the page.
  """
  def watch_browser(%{conn: conn}) do
    :ok = PlaywrightEx.subscribe(conn.context_id)
    :ok = PlaywrightEx.subscribe(conn.page_id)

    {:ok, _} =
      BrowserContext.add_init_script(conn.context_id,
        source: @record_csp_violations,
        timeout: Playwright.Config.global(:timeout)
      )

    :ok
  end

  @doc """
  Asserts the current page saw no CSP violation, and that no console error
  or uncaught page error happened since the test started.
  """
  def assert_clean_browser(conn) do
    Playwright.evaluate(conn, "window.__cspViolations", fn violations ->
      assert violations == [], "CSP violations: #{inspect(violations)}"
    end)

    # The evaluate round trip above passed every earlier browser event to this process.
    errors = browser_errors([])
    assert errors == [], "Browser errors: #{inspect(errors)}"

    conn
  end

  defp browser_errors(acc) do
    receive do
      {:playwright_msg, %{method: :console, params: %{type: "error"} = params}} ->
        browser_errors([params.text | acc])

      {:playwright_msg, %{method: :page_error, params: %{error: %{error: error}}}} ->
        browser_errors(["#{error[:name]}: #{error[:message]}" | acc])

      {:playwright_msg, %{method: :page_error, params: params}} ->
        browser_errors([inspect(params) | acc])

      {:playwright_msg, _other} ->
        browser_errors(acc)
    after
      0 -> Enum.reverse(acc)
    end
  end
end
