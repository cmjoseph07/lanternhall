defmodule LanternhallWeb.E2E.Platform.ThemeTest do
  # Dark and light themes from the logo palette, the top bar toggle, no flash of
  # the wrong theme, WCAG 2.2 AA contrast and system fonts (SPEC-platform.md section 3.6).
  #
  # The browser context emulates `prefers-color-scheme: light` (Playwright's default),
  # so a dark first visit proves the default is dark rather than the system's choice.
  use LanternhallWeb.E2ECase

  alias PhoenixTest.Playwright
  alias PlaywrightEx.BrowserContext

  @dark "lanternhall-dark"
  @light "lanternhall-light"

  # Runs before the page's own scripts on every load: logs each `data-theme` the
  # root element takes, and what the root looks like in the first frame, which the
  # browser renders right after `requestAnimationFrame` callbacks run.
  @record_theme_frames """
  window.__themeLog = [];
  new MutationObserver((records) => {
    for (const record of records) {
      if (record.target === document.documentElement) {
        window.__themeLog.push(record.target.getAttribute("data-theme"));
      }
    }
  }).observe(document, { subtree: true, attributes: true, attributeFilter: ["data-theme"] });
  requestAnimationFrame(() => {
    window.__firstFrame = {
      theme: document.documentElement.getAttribute("data-theme"),
      background: getComputedStyle(document.documentElement).backgroundColor
    };
  });
  """

  @background %{@dark => "rgb(18, 18, 34)", @light => "rgb(255, 255, 255)"}

  setup %{conn: conn} do
    {:ok, _} =
      BrowserContext.add_init_script(conn.context_id,
        source: @record_theme_frames,
        timeout: Playwright.Config.global(:timeout)
      )

    :ok
  end

  test "first visit renders dark from the first frame", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_first_frame(@dark)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_pressed("dark")
    |> assert_clean_browser()
  end

  test "a light choice survives reload with no dark frame, and dark survives with no light frame",
       %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> choose_theme("light")
    |> assert_has("html[data-theme=#{@light}]")
    |> assert_pressed("light")
    |> visit(~p"/")
    |> assert_first_frame(@light)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_pressed("light")
    |> choose_theme("dark")
    |> assert_has("html[data-theme=#{@dark}]")
    |> visit(~p"/")
    |> assert_first_frame(@dark)
    |> assert_clean_browser()
  end

  test "system follows the operating system's color scheme and survives reload",
       %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> choose_theme("system")
    |> assert_has("html[data-theme=#{@light}]")
    |> visit(~p"/")
    |> assert_first_frame(@light)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_pressed("system")
    |> assert_clean_browser()
  end

  test "the toggle's buttons are named for screen readers", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(
      ~s|[...document.querySelectorAll("#theme-toggle button")].map((b) => b.getAttribute("aria-label"))|,
      fn labels -> assert labels == ["System theme", "Light theme", "Dark theme"] end
    )
  end

  # WCAG 2.2 AA 1.4.3: text needs 4.5:1 against what it sits on. Each pair is
  # {text color, opacity, background}; opacity 0.7 is the muted text the pages use
  # (`text-base-content/70`), and primary is the color of links and active states.
  @text_pairs (for base <- ~w(base-100 base-200 base-300),
                   {text, opacity} <- [{"base-content", 1}, {"base-content", 0.7}, {"primary", 1}] do
                 [text, opacity, base]
               end) ++
                for(
                  color <- ~w(primary secondary accent neutral info success warning error),
                  do: ["#{color}-content", 1, color]
                )

  # Paints each pair onto a 1x1 canvas the way the browser composites it, and reads
  # back the sRGB pixels of the background and of the text over it. A color the
  # theme leaves undefined, or the canvas cannot parse, throws instead of passing.
  @paint_pairs """
  ((pairs, themes) => {
    const canvas = Object.assign(document.createElement("canvas"), { width: 1, height: 1 });
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    const probe = document.body.appendChild(document.createElement("div"));
    const resolve = (name) => {
      if (getComputedStyle(probe).getPropertyValue(`--color-${name}`).trim() === "") {
        throw new Error(`${probe.dataset.theme} has no --color-${name}`);
      }
      probe.style.color = `var(--color-${name})`;
      return getComputedStyle(probe).color;
    };
    const paint = (name, opacity) => {
      const color = resolve(name);
      ctx.fillStyle = "#010203";
      ctx.fillStyle = color;
      if (ctx.fillStyle === "#010203") throw new Error(`canvas cannot parse ${color}`);
      ctx.globalAlpha = opacity;
      ctx.fillRect(0, 0, 1, 1);
      return [...ctx.getImageData(0, 0, 1, 1).data.slice(0, 3)];
    };
    const result = {};
    for (const theme of themes) {
      probe.dataset.theme = theme;
      result[theme] = pairs.map(([text, opacity, background]) => {
        const bg = paint(background, 1);
        return { pair: `${text}@${opacity} on ${background}`, bg, fg: paint(text, opacity) };
      });
    }
    probe.remove();
    return result;
  })
  """

  test "every text color pair meets WCAG 2.2 AA contrast in both themes", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> Playwright.evaluate(
      "#{@paint_pairs}(#{JSON.encode!(@text_pairs)}, #{JSON.encode!([@dark, @light])})",
      fn by_theme ->
        failures =
          for {theme, pairs} <- by_theme,
              %{"pair" => pair, "bg" => bg, "fg" => fg} <- pairs,
              ratio = contrast(fg, bg),
              ratio < 4.5,
              do: "#{theme}: #{pair} is #{Float.round(ratio, 2)}:1"

        assert map_size(by_theme) == 2
        assert failures == []
      end
    )
    |> assert_clean_browser()
  end

  # WCAG 2.2 AA as the page renders, once running animations (such as a flash fading
  # in) finish: each background behind an element is painted at its node's opacity
  # (its own times its ancestors'), then the element's color at its full opacity, and
  # both are read back as sRGB. Icons are masks filled with `background-color`, so
  # that is their color. Each entry is [selector, minimum ratio]: 4.5:1 for text
  # (1.4.3), 3:1 for icons (1.4.11).
  @paint_rendered """
  (async (entries) => {
    await Promise.all(document.getAnimations().map((animation) => animation.finished));
    const canvas = Object.assign(document.createElement("canvas"), { width: 1, height: 1 });
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    const paint = (color, alpha) => {
      ctx.globalAlpha = 1;
      ctx.fillStyle = "#010203";
      ctx.fillStyle = color;
      if (ctx.fillStyle === "#010203") throw new Error(`canvas cannot parse ${color}`);
      ctx.globalAlpha = alpha;
      ctx.fillRect(0, 0, 1, 1);
      return [...ctx.getImageData(0, 0, 1, 1).data.slice(0, 3)];
    };
    return entries.map(([selector, minimum]) => {
      const el = document.querySelector(selector);
      if (!el) throw new Error(`nothing matches ${selector}`);
      const icon = [...el.classList].some((c) => c.startsWith("hero-"));
      const chain = [];
      for (let node = el; node; node = node.parentElement) chain.unshift(node);
      ctx.clearRect(0, 0, 1, 1);
      let bg = paint("#ffffff", 1);
      let opacity = 1;
      for (const node of chain) {
        const style = getComputedStyle(node);
        opacity *= Number(style.opacity);
        if (node !== el || !icon) bg = paint(style.backgroundColor, opacity);
      }
      const style = getComputedStyle(el);
      const fg = paint(icon ? style.backgroundColor : style.color, opacity);
      return { selector, minimum, bg, fg };
    });
  })
  """

  @flash_parts (for kind <- ~w(info error),
                    {part, minimum} <- [
                      {"p", 4.5},
                      {"[class*=hero-]:not(button *)", 3},
                      {"button [class*=hero-]", 3}
                    ] do
                  ["#flash-#{kind} #{part}", minimum]
                end)

  test "flash text and icons meet WCAG 2.2 AA contrast in both themes", %{conn: conn} do
    conn
    |> visit(~p"/fixtures/core?flashes")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("html[data-theme=#{@dark}]")
    |> assert_rendered_contrast(@flash_parts)
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> choose_theme("light")
    |> visit(~p"/fixtures/core?flashes")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("html[data-theme=#{@light}]")
    |> assert_rendered_contrast(@flash_parts)
    |> assert_clean_browser()
  end

  test "the logo is inline and its wordmark follows the theme's text color", %{conn: conn} do
    wordmark_and_text =
      ~s|[getComputedStyle(document.querySelector('#landing-logo svg g[fill="currentColor"]')).fill, | <>
        ~s|getComputedStyle(document.documentElement).color]|

    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(wordmark_and_text, fn [fill, text] ->
      assert fill == text
      assert fill == "rgb(233, 231, 245)"
    end)
    |> choose_theme("light")
    |> assert_has("html[data-theme=#{@light}]")
    |> Playwright.evaluate(wordmark_and_text, fn [fill, text] ->
      assert fill == text
      assert fill == "rgb(18, 18, 34)"
    end)
  end

  test "system font stacks only: no font file, font face or preload", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(
      """
      (() => {
        const code = document.body.appendChild(document.createElement("code"));
        const result = {
          fontFaces: document.fonts.size,
          fontRequests: performance.getEntriesByType("resource")
            .filter((e) => e.initiatorType === "css" || /\\.(woff2?|ttf|otf|eot)(\\?|$)/.test(e.name))
            .map((e) => e.name),
          preloads: [...document.querySelectorAll("link[rel=preload]")].map((l) => l.href),
          sans: getComputedStyle(document.body).fontFamily,
          mono: getComputedStyle(code).fontFamily
        };
        code.remove();
        return result;
      })()
      """,
      fn result ->
        assert %{"fontFaces" => 0, "fontRequests" => [], "preloads" => []} = result
        assert result["sans"] =~ ~r/^system-ui, /
        assert result["mono"] =~ ~r/^ui-monospace, /
      end
    )
    |> assert_clean_browser()
  end

  defp choose_theme(conn, choice),
    do: Playwright.click(conn, "#theme-toggle button[data-phx-theme=#{choice}]")

  defp assert_pressed(conn, choice) do
    conn
    |> assert_has("#theme-toggle button[data-phx-theme=#{choice}][aria-pressed=true]")
    |> Playwright.evaluate(
      ~s|document.querySelectorAll('#theme-toggle button[aria-pressed="true"]').length|,
      fn pressed -> assert pressed == 1 end
    )
  end

  # The root took exactly one theme, before the first frame was painted.
  defp assert_first_frame(conn, theme) do
    conn
    |> Playwright.evaluate("window.__themeLog", fn log -> assert log == [theme] end)
    |> Playwright.evaluate("window.__firstFrame", fn frame ->
      assert frame == %{"theme" => theme, "background" => @background[theme]}
    end)
  end

  defp assert_rendered_contrast(conn, entries) do
    Playwright.evaluate(conn, "#{@paint_rendered}(#{JSON.encode!(entries)})", fn measured ->
      failures =
        for %{"selector" => selector, "minimum" => minimum, "bg" => bg, "fg" => fg} <- measured,
            ratio = contrast(fg, bg),
            ratio < minimum,
            do: "#{selector} is #{Float.round(ratio, 2)}:1, needs #{minimum}:1"

      assert length(measured) == length(entries)
      assert failures == []
    end)
  end

  # WCAG 2.2 contrast ratio of two sRGB colors (https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio).
  defp contrast(a, b) do
    [darker, lighter] = Enum.sort([luminance(a), luminance(b)])
    (lighter + 0.05) / (darker + 0.05)
  end

  defp luminance(rgb) do
    [r, g, b] =
      for channel <- rgb do
        c = channel / 255
        if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
