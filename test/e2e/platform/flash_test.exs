defmodule LanternhallWeb.E2E.Platform.FlashTest do
  use LanternhallWeb.E2ECase

  alias Phoenix.LiveView.Debug
  alias PhoenixTest.Playwright

  @boxes """
  (async () => {
    await Promise.all(document.getAnimations().map((animation) => animation.finished));
    const box = (selector) => {
      const rect = document.querySelector(selector).getBoundingClientRect();
      return [rect.left, rect.top, rect.right, rect.bottom];
    };
    return {
      header: box("header"),
      toggle: box("#theme-toggle"),
      info: box("#flash-info"),
      error: box("#flash-error")
    };
  })()
  """

  for width <- [1024, 1920] do
    test "flashes stack below the top bar at #{width} px, aligned with its controls",
         %{conn: conn} do
      conn
      |> set_viewport(unquote(width), 900)
      |> visit(~p"/fixtures/core?flashes")
      |> assert_has("[data-phx-main].phx-connected")
      |> Playwright.evaluate(@boxes, fn boxes ->
        %{"header" => header, "toggle" => toggle, "info" => info, "error" => error} = boxes

        refute overlap?(info, error), "the flashes overlap: #{inspect(boxes)}"
        refute overlap?(header, info), "the info flash covers the top bar: #{inspect(boxes)}"
        refute overlap?(header, error), "the error flash covers the top bar: #{inspect(boxes)}"
        assert Enum.at(info, 2) == Enum.at(toggle, 2)
        assert Enum.at(error, 2) == Enum.at(toggle, 2)
      end)
      |> Playwright.click("#theme-toggle button[data-phx-theme=light]")
      |> assert_has("html[data-theme=lanternhall-light]")
      |> assert_clean_browser()
    end
  end

  @announcements """
  (() => {
    const live = "[aria-live]:not([aria-live=off]), [role=alert], [role=status], [role=log]";
    return ["#flash-info", "#flash-error", "#client-error", "#server-error"].map((selector) => {
      const flash = document.querySelector(selector);
      const regions = [];
      for (let node = flash; node; node = node.parentElement) {
        if (node.matches(live)) {
          regions.push(`${node.id} ${node.getAttribute("aria-live") || node.getAttribute("role")}`);
        }
      }
      return { flash: selector, regions, close: flash.querySelector("button").getAttribute("aria-label") };
    });
  })()
  """

  # A flash inside two live regions is read out twice: once by each.
  test "a screen reader hears each flash once, and its close button is named Close",
       %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core?flashes")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(@announcements, fn flashes ->
      assert flashes ==
               for(
                 flash <- ~w(#flash-info #flash-error #client-error #server-error),
                 do: %{"flash" => flash, "regions" => ["flash-group polite"], "close" => "Close"}
               )
    end)
    |> assert_clean_browser()
  end

  @flashes_after_close """
  (closed) => new Promise((resolve) => {
    const group = document.getElementById("flash-group");
    const settle = () => {
      if (group.querySelector(closed)) return false;
      resolve(["#flash-info", "#flash-error"].filter((selector) => group.querySelector(selector)));
      return true;
    };
    if (settle()) return;
    new MutationObserver((_records, observer) => settle() && observer.disconnect())
      .observe(group, { childList: true });
  })
  """

  for {closed, kept} <- [{"#flash-info", "#flash-error"}, {"#flash-error", "#flash-info"}] do
    test "Close on #{closed} dismisses it and leaves #{kept}", %{conn: conn} do
      conn
      |> visit(~p"/fixtures/core?flashes")
      |> assert_has("[data-phx-main].phx-connected")
      |> Playwright.click("#{unquote(closed)} button[aria-label=Close]")
      |> refute_has(unquote(closed))
      |> Playwright.evaluate(
        @flashes_after_close,
        [is_function: true, arg: unquote(closed)],
        fn flashes -> assert flashes == [unquote(kept)] end
      )
      |> assert_has(unquote(kept))
      |> assert_clean_browser()
    end
  end

  test "the client notice shows while the socket is down and goes when it is back",
       %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core")
    |> assert_has("[data-phx-main].phx-connected")
    |> refute_has("#client-error")
    |> Playwright.evaluate("window.liveSocket.disconnect()")
    |> assert_has("#client-error")
    |> refute_has("#server-error")
    |> Playwright.evaluate("window.liveSocket.connect()")
    |> assert_has("[data-phx-main].phx-connected")
    |> refute_has("#client-error")
    |> assert_clean_browser()
  end

  # LiveView sends `phx:show-end` when the show transition's time is up and takes the
  # transition's classes off in the next frame. The notice's spinner never stops, so
  # waiting on `document.getAnimations()` here would never end.
  @notice_beside_flash """
  (async () => {
    const notice = document.getElementById("client-error");
    const shown = new Promise((resolve) => {
      notice.addEventListener("phx:show-end", resolve, { once: true });
    });
    const frame = () => new Promise((resolve) => requestAnimationFrame(resolve));
    window.liveSocket.disconnect();
    await shown;
    await frame();
    await frame();
    const layout = (selector) => {
      const button = document.querySelector(`${selector} button[aria-label=Close]`);
      const alert = button.closest(".alert");
      const box = alert.getBoundingClientRect();
      const close = button.getBoundingClientRect();
      return {
        display: getComputedStyle(alert).display,
        width: box.width,
        close: [box.right - close.right, close.top - box.top]
      };
    };
    return { flash: layout("#flash-info"), notice: layout("#client-error") };
  })()
  """

  # Showing a notice must not change its layout: LiveView shows an element by writing an
  # inline `display` on it, and one written on the alert itself would replace its grid.
  test "a reconnect notice is laid out as a flash is, with Close at the top right",
       %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core?flashes")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(@notice_beside_flash, fn %{"flash" => flash, "notice" => notice} ->
      assert notice["display"] == "grid"
      assert notice == flash
    end)
    |> assert_has("#client-error")
    |> assert_clean_browser()
  end

  # The page rejoins by itself about half a second after the notice shows, too short to
  # catch by polling, so the page records each change of the notice's `hidden` attribute.
  @watch_server_notice """
  void (window.__serverNotice = new Promise((resolve) => {
    const notice = document.getElementById("server-error");
    const log = [];
    new MutationObserver(() => {
      log.push(notice.hidden ? "hidden" : "shown");
      if (notice.hidden) resolve(log);
    }).observe(notice, { attributes: true, attributeFilter: ["hidden"] });
  }))
  """

  test "the server notice shows when the page's process dies and goes once it has rejoined",
       %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core")
    |> assert_has("[data-phx-main].phx-connected")
    |> refute_has("#server-error")
    |> Playwright.evaluate(@watch_server_notice)
    |> kill_live_view()
    # The client waits a second before it rejoins, half of the default timeout.
    |> Playwright.evaluate("window.__serverNotice", [timeout: 5_000], fn log ->
      assert log == ["shown", "hidden"]
    end)
    |> assert_has("[data-phx-main].phx-connected")
    |> refute_has("#server-error")
    |> refute_has("#client-error")
    |> assert_clean_browser()
  end

  defp kill_live_view(conn) do
    Playwright.evaluate(conn, "document.querySelector('[data-phx-main]').id", fn id ->
      [%{pid: pid}] =
        Enum.filter(Debug.list_liveviews(), &(&1.topic == "lv:" <> id))

      Process.exit(pid, :kill)
    end)
  end

  defp overlap?([l1, t1, r1, b1], [l2, t2, r2, b2]),
    do: l1 < r2 and l2 < r1 and t1 < b2 and t2 < b1

  # PlaywrightEx has no function for this yet; it sends the Playwright protocol message
  # behind `page.setViewportSize` (https://playwright.dev/docs/api/class-page).
  defp set_viewport(conn, width, height) do
    reply =
      PlaywrightEx.send(
        %{
          guid: conn.page_id,
          method: :set_viewport_size,
          params: %{viewport_size: %{width: width, height: height}}
        },
        timeout: Playwright.Config.global(:timeout)
      )

    refute Map.has_key?(reply, :error), "setViewportSize failed: #{inspect(reply)}"
    conn
  end
end
