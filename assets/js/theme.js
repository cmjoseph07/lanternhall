;(() => {
  const root = document.documentElement
  const systemDark = matchMedia("(prefers-color-scheme: dark)")
  const choices = ["system", "light", "dark"]

  const apply = (stored) => {
    const choice = choices.includes(stored) ? stored : "dark"
    const mode = choice === "system" ? (systemDark.matches ? "dark" : "light") : choice
    root.setAttribute("data-theme", `lanternhall-${mode}`)
    root.setAttribute("data-theme-choice", choice)
  }

  // Reading `localStorage` throws when the browser blocks site storage, and writing
  // throws when it is full. The choice then lives only in `data-theme-choice`, for as
  // long as this page is open.
  const load = () => {
    try {
      return localStorage.getItem("phx:theme")
    } catch {
      return null
    }
  }
  const save = (choice) => {
    try {
      localStorage.setItem("phx:theme", choice)
    } catch {}
  }

  apply(load())
  // Another tab changed the choice, or cleared all of the site's storage (no key).
  window.addEventListener("storage", (e) => {
    if (e.key === "phx:theme" || e.key === null) apply(load())
  })
  window.addEventListener("phx:set-theme", (e) => {
    save(e.target.dataset.phxTheme)
    apply(e.target.dataset.phxTheme)
  })
  systemDark.addEventListener("change", () => {
    if (root.getAttribute("data-theme-choice") === "system") apply("system")
  })
})()
