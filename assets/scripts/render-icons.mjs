// Renders the favicon and PWA icons from priv/static/images/logo-mark.svg
// (SPEC-platform.md section 3.8). Run with `pnpm --dir assets run icons`.
//
// Uses the Chromium that Playwright already pins for the E2E tests, so no image
// library is needed. The output is committed; this script is the only way to change it.

import { readFile, writeFile } from "node:fs/promises"
import { chromium } from "playwright"

const images = new URL("../../priv/static/images/", import.meta.url)

// Background of the opaque icons: the logo's ink, the dark theme's base color.
// Keep in sync with `background_color` and `theme_color` in priv/static/manifest.webmanifest.
const ink = "#121222"

// `markSize` is the mark's share of the icon edge. The maskable icon keeps the
// mark inside the central 80% circle that every platform mask leaves visible
// (https://w3c.github.io/manifest/#icon-masks); the touch icon leaves room for
// the rounded corners iOS cuts.
const pngs = [
  { name: "favicon-32.png", size: 32, markSize: 1 },
  { name: "icon-192.png", size: 192, markSize: 1 },
  { name: "icon-512.png", size: 512, markSize: 1 },
  { name: "apple-touch-icon.png", size: 180, markSize: 0.8, background: ink },
  { name: "icon-maskable-512.png", size: 512, markSize: 0.6875, background: ink },
]

const mark = await readFile(new URL("logo-mark.svg", images), "utf8")

// The favicon is the mark itself, minus the comments a browser never needs.
await writeFile(new URL("favicon.svg", images), mark.replace(/\n?\s*<!--.*?-->/gs, ""))

const browser = await chromium.launch()

try {
  const page = await browser.newPage({ deviceScaleFactor: 1 })

  for (const { name, size, markSize, background } of pngs) {
    const edge = Math.round(size * markSize)
    const inset = (size - edge) / 2

    await page.setViewportSize({ width: size, height: size })
    await page.setContent(`<!DOCTYPE html>
      <body style="margin: 0; background: ${background ?? "transparent"}">
        <img src="data:image/svg+xml;base64,${Buffer.from(mark).toString("base64")}"
             width="${edge}" height="${edge}"
             style="display: block; margin: ${inset}px">
      </body>`)
    await page.locator("img").evaluate((img) => img.decode())

    const png = await page.screenshot({ omitBackground: !background, type: "png" })
    await writeFile(new URL(name, images), png)
    console.log(`wrote priv/static/images/${name}`)
  }
} finally {
  await browser.close()
}
