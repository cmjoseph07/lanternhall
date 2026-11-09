defmodule LanternhallWeb.E2E.Platform.PWATest do
  # Lanternhall installs as an app from its manifest alone, without a service
  # worker (SPEC-platform.md sections 3.8 and 11).
  #
  # Headless Chromium has no install UI: `beforeinstallprompt` never fires and
  # `Page.getInstallabilityErrors` answers `[]` even for a broken manifest. So this
  # test checks what install depends on (Chromium's own parse of the manifest, every
  # icon fetched and decoded at its declared size, no service worker), and the Install
  # offer itself is checked by hand in Chrome and Edge.
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright

  test "Chromium parses the manifest and loads its icons; no service worker, no image on load",
       %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> assert_has("[data-phx-main].phx-connected")
      # The icons are for the browser, not the page: Landing loads no image.
      |> Playwright.evaluate(
        ~s|performance.getEntriesByType("resource").filter((e) => e.initiatorType === "img").map((e) => e.name)|,
        fn images -> assert images == [] end
      )
      |> Playwright.evaluate("navigator.serviceWorker.getRegistrations()", fn registrations ->
        assert registrations == []
      end)

    origin = LanternhallWeb.Endpoint.url()

    assert %{"url" => url, "errors" => [], "manifest" => manifest} =
             conn |> cdp_session() |> cdp_send("Page.getAppManifest")

    assert url == origin <> ~p"/manifest.webmanifest"

    assert Map.take(manifest, ~w(id name start_url scope display theme_color background_color)) ==
             %{
               "id" => origin <> "/",
               "name" => "Lanternhall",
               "start_url" => origin <> "/",
               "scope" => origin <> "/",
               "display" => "kStandalone",
               "theme_color" => "rgba(18,18,34,1)",
               "background_color" => "rgba(18,18,34,1)"
             }

    icons = for icon <- manifest["icons"], do: [icon["url"], icon["sizes"]]

    assert icons == [
             [origin <> "/images/icon-192.png", "192x192"],
             [origin <> "/images/icon-512.png", "512x512"],
             [origin <> "/images/icon-maskable-512.png", "512x512"]
           ]

    conn
    |> Playwright.evaluate(
      """
      Promise.all(#{JSON.encode!(Enum.map(icons, &hd/1))}.map(async (src) => {
        const img = new Image()
        img.src = src
        await img.decode()
        return `${img.naturalWidth}x${img.naturalHeight}`
      }))
      """,
      fn sizes -> assert sizes == Enum.map(icons, &List.last/1) end
    )
    |> assert_clean_browser()
  end

  # PlaywrightEx has no function for a Chrome DevTools Protocol session yet, so these
  # send the Playwright protocol messages behind `BrowserContext.newCDPSession` and
  # `CDPSession.send` (https://playwright.dev/docs/api/class-cdpsession).
  defp cdp_session(conn) do
    %{result: %{session: %{guid: session}}} =
      PlaywrightEx.send(
        %{guid: conn.context_id, method: "newCDPSession", params: %{page: %{guid: conn.page_id}}},
        timeout: Playwright.Config.global(:timeout)
      )

    session
  end

  # PlaywrightEx turns result keys into atoms where such an atom happens to exist;
  # string keys throughout keep the assertions independent of that.
  defp cdp_send(session, method) do
    %{result: %{result: result}} =
      PlaywrightEx.send(
        %{guid: session, method: :send, params: %{method: method}},
        timeout: Playwright.Config.global(:timeout)
      )

    string_keys(result)
  end

  defp string_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), string_keys(value)} end)

  defp string_keys(list) when is_list(list), do: Enum.map(list, &string_keys/1)
  defp string_keys(value), do: value
end
