defmodule LanternhallWeb.E2E.Platform.FlashTest do
  # Flashes stack in one column below the top bar, right-aligned with its controls, so
  # none hides another or the top bar, at the widths the pixel check uses
  # (SPEC-platform.md section 8).
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright

  # Each visible part's box once animations finish, as [left, top, right, bottom].
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
