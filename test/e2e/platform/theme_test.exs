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

  # WCAG 2.2 AA as each page renders, measured in the browser once animations and
  # transitions finish. Every visible element with its own text is held to 4.5:1
  # (1.4.3; 3:1 for large text), every icon to 3:1 (1.4.11; icons are masks filled with
  # `background-color`), and every focusable element must show a focus ring of 3:1
  # against what lies around it (2.4.7, 1.4.11). Logos are exempt (1.4.3).
  #
  # The color behind a point is what the browser stacks there: each element under it,
  # from the root up, painted at its effective opacity onto a 1x1 canvas, so a sibling
  # drawn behind an element (the toggle's thumb) counts like an ancestor's background.
  @measure_page """
  (async () => {
    const settle = () => Promise.all(document.getAnimations().map((a) => a.finished));
    await settle();
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
    const opacity = (node) => {
      let o = 1;
      for (let n = node; n; n = n.parentElement) o *= Number(getComputedStyle(n).opacity);
      return o;
    };
    // What lies under (x, y) below `el` (and `el` itself when `withSelf`), bottom first.
    const backdrop = (x, y, el, withSelf) => {
      const hits = document.elementsFromPoint(x, y);
      let below = hits;
      if (el) {
        const at = hits.indexOf(el);
        below = [];
        if (at >= 0) below = hits.slice(at + 1);
        else for (let n = el.parentElement; n; n = n.parentElement) below.push(n);
        if (withSelf) below.unshift(el);
      }
      ctx.clearRect(0, 0, 1, 1);
      let bg = paint("#ffffff", 1);
      for (const node of below.reverse()) bg = paint(getComputedStyle(node).backgroundColor, opacity(node));
      return bg;
    };
    const name = (el) => {
      const icon = [...el.classList].find((c) => c.startsWith("hero-"));
      if (icon) return `${icon} in ${name(el.closest("[aria-label]") || el.parentElement)}`;
      const label = el.getAttribute("aria-label") || el.textContent.trim().slice(0, 30);
      return `${el.tagName.toLowerCase()}${el.id ? "#" + el.id : ""} "${label}"`;
    };
    const visible = (el) => {
      const rect = el.getBoundingClientRect();
      return el.checkVisibility({ visibilityProperty: true }) && rect.width > 1 && rect.height > 1;
    };
    const center = (el) => {
      const rect = el.getBoundingClientRect();
      return [rect.left + rect.width / 2, rect.top + rect.height / 2];
    };
    const exempt = (el) => el.closest("[role=img], script, style, template");
    const all = [...document.body.querySelectorAll("*")].filter((el) => !exempt(el) && visible(el));
    const results = [];

    for (const el of all) {
      const style = getComputedStyle(el);
      const icon = [...el.classList].some((c) => c.startsWith("hero-"));
      const ownText = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
      if (!icon && !ownText) continue;
      const size = parseFloat(style.fontSize);
      const large = size >= 24 || (size >= 18.66 && Number(style.fontWeight) >= 700);
      const [x, y] = center(el);
      const bg = backdrop(x, y, el, !icon);
      const fg = paint(icon ? style.backgroundColor : style.color, opacity(el));
      results.push({ what: `${icon ? "icon" : "text"} ${name(el)}`, minimum: icon || large ? 3 : 4.5, bg, fg });
    }

    const focusable = all.filter((el) => el.matches("a[href], button, input, select, textarea, [tabindex]"));
    for (const el of focusable) {
      el.focus({ focusVisible: true });
      await settle();
      const style = getComputedStyle(el);
      if (!el.matches(":focus-visible") || style.outlineStyle === "none" || parseFloat(style.outlineWidth) === 0) {
        results.push({ what: `focus ring ${name(el)}`, problem: "shows no focus ring" });
      } else {
        const rect = el.getBoundingClientRect();
        const ring = parseFloat(style.outlineOffset) + parseFloat(style.outlineWidth) / 2;
        const bg = backdrop(rect.right + ring, rect.top + rect.height / 2, null, false);
        const fg = paint(style.outlineColor, opacity(el));
        results.push({ what: `focus ring ${name(el)}`, minimum: 3, bg, fg });
      }
      el.blur();
    }
    await settle();
    return results;
  })()
  """

  @pages ["/", "/settings", "/fixtures/core?flashes"]

  test "every rendered text, icon and focus ring meets WCAG 2.2 AA contrast in both themes",
       %{conn: conn} do
    conn
    |> assert_pages_contrast(@dark)
    |> visit(~p"/")
    |> assert_has("[data-phx-main].phx-connected")
    |> choose_theme("light")
    |> assert_pages_contrast(@light)
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

  defp assert_pages_contrast(conn, theme),
    do: Enum.reduce(@pages, conn, &assert_page_contrast(&2, &1, theme))

  defp assert_page_contrast(conn, page, theme) do
    conn
    |> visit(page)
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_has("html[data-theme=#{theme}]")
    |> Playwright.evaluate(@measure_page, fn measured ->
      kinds = measured |> Enum.map(&(&1["what"] |> String.split(" ") |> hd())) |> Enum.uniq()

      failures =
        for entry <- measured,
            failure = contrast_failure(entry),
            do: "#{theme} #{page}: #{entry["what"]} #{failure}"

      assert Enum.sort(kinds) == ["focus", "icon", "text"],
             "#{page} measured only #{inspect(kinds)}"

      assert failures == []
    end)
  end

  defp contrast_failure(%{"problem" => problem}), do: problem

  defp contrast_failure(%{"minimum" => minimum, "bg" => bg, "fg" => fg}) do
    ratio = contrast(fg, bg)
    if ratio < minimum, do: "is #{Float.round(ratio, 2)}:1, needs #{minimum}:1"
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
