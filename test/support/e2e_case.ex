defmodule LanternhallWeb.E2ECase do
  @moduledoc """
  Real-browser test case: `PhoenixTest.Playwright.Case` in headless Chromium
  against the test server at http://localhost:4002, tagged `:e2e`.

  Every page of a test's browser context is watched from its first request, and the
  test fails when it ends if a console error or an uncaught page error happened in
  any of them. Chromium reports a Content-Security-Policy violation as a console error.

  `@tag browser_errors: [...]` lists the errors a test expects, in order, such as the
  browser's own report of a 404 page; the errors must match it exactly.
  `@tag browser_errors: ~r/.../` is for an error whose text or count varies: at least
  one error happened and every error matches.
  """
  use ExUnit.CaseTemplate

  alias LanternhallWeb.BrowserWatcher
  alias PhoenixTest.Playwright
  alias PlaywrightEx.BrowserContext

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
  Watches the test's browser context and, when the test ends, asserts its errors
  are the ones under the `:browser_errors` tag.
  """
  def watch_browser(%{conn: conn} = context) do
    {:ok, watcher} = BrowserWatcher.start(conn)

    on_exit(fn ->
      try do
        assert_browser_errors(watcher, Map.get(context, :browser_errors, []))
      after
        BrowserWatcher.stop(watcher)
      end
    end)

    [browser_watcher: watcher]
  end

  @doc """
  Asserts the console errors and uncaught page errors of every page so far.
  """
  def assert_browser_errors(watcher, %Regex{} = pattern) do
    errors = BrowserWatcher.errors(watcher)

    assert errors != []
    assert Enum.reject(errors, &(&1 =~ pattern)) == []
  end

  def assert_browser_errors(watcher, expected) do
    assert BrowserWatcher.errors(watcher) == expected
  end

  @doc """
  Opens another page in the browser context of `conn` and returns a session on it.
  """
  def open_tab(conn) do
    {:ok, page} =
      BrowserContext.new_page(conn.context_id, timeout: Playwright.Config.global(:timeout))

    %{conn | page_id: page.guid, frame_id: page.main_frame.guid}
  end
end
