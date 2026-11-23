// Phoenix extracts each hook from its HEEx template as written, so the extracted file
// keeps the template's indentation and the blank line after the <script> tag, which no
// formatter accepts. This writes a copy of each hook without them and hands the copies
// to Biome, so a hook is held to the same rules as the JS in assets/js.

import { spawnSync } from "node:child_process"
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises"
import { join, resolve } from "node:path"

if (!process.argv[2]) {
  throw new Error("usage: check-colocated-hooks.mjs <build path, such as ../_build/test>")
}

const build = resolve(process.argv[2])
const extracted = join(build, "phoenix-colocated", "lanternhall")
const copies = join(build, "lanternhall-hooks-dedented")

function dedent(source) {
  const lines = source
    .replace(/^(\s*\n)+/, "")
    .trimEnd()
    .split("\n")
  const indents = lines.filter((line) => line.trim() !== "").map((line) => line.search(/\S/))
  const shared = Math.min(...indents)

  return `${lines.map((line) => line.slice(shared)).join("\n")}\n`
}

await rm(copies, { recursive: true, force: true })

// One directory per module that has a hook; `node_modules` is a link, so it is skipped.
const modules = (await readdir(extracted, { withFileTypes: true })).filter((entry) =>
  entry.isDirectory(),
)
let count = 0

for (const { name: module } of modules) {
  const hooks = (await readdir(join(extracted, module))).filter((file) => file.endsWith(".js"))
  await mkdir(join(copies, module), { recursive: true })

  for (const hook of hooks) {
    const source = await readFile(join(extracted, module, hook), "utf8")
    await writeFile(join(copies, module, hook), dedent(source))
    count += 1
  }
}

if (count === 0) {
  throw new Error(`no colocated hook found in ${extracted}`)
}

const biome = spawnSync("biome", ["check", "--error-on-warnings", copies], { stdio: "inherit" })

if (biome.error) {
  throw biome.error
}

process.exitCode = biome.status ?? 1
