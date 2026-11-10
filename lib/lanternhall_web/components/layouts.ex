defmodule LanternhallWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LanternhallWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/"} class="text-sm font-semibold">Lanternhall</.link>
      </div>
      <div class="flex-none">
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="toast toast-top toast-end top-16 end-4 z-50 sm:end-6 lg:end-8"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  The top bar's theme toggle: system, light or dark.

  A click dispatches `phx:set-theme`, which the inline script in
  `root.html.heex` handles: it stores the choice and sets `data-theme` and
  `data-theme-choice` on `<html>`. The highlight follows `data-theme-choice` in
  CSS, so it is right from the first frame; the `.ThemeToggle` hook mirrors the
  choice into `aria-pressed` for screen readers, and `phx-update="ignore"` keeps
  LiveView from patching those attributes away.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      phx-hook=".ThemeToggle"
      phx-update="ignore"
      role="group"
      aria-label="Theme"
      class="relative flex rounded-full bg-base-300 p-0.5"
    >
      <div
        aria-hidden="true"
        class="absolute top-0.5 left-0.5 size-8 rounded-full bg-primary motion-safe:transition-transform [[data-theme-choice=light]_&]:translate-x-8 [[data-theme-choice=dark]_&]:translate-x-16"
      />
      <button
        :for={
          {choice, label, icon, selected} <- [
            {"system", "System theme", "hero-computer-desktop-micro",
             "[[data-theme-choice=system]_&]:text-primary-content!"},
            {"light", "Light theme", "hero-sun-micro",
             "[[data-theme-choice=light]_&]:text-primary-content!"},
            {"dark", "Dark theme", "hero-moon-micro",
             "[[data-theme-choice=dark]_&]:text-primary-content!"}
          ]
        }
        type="button"
        data-phx-theme={choice}
        aria-label={label}
        phx-click={JS.dispatch("phx:set-theme")}
        class={[
          "relative flex size-8 cursor-pointer items-center justify-center rounded-full",
          "text-base-content/70 hover:text-base-content motion-safe:transition-colors",
          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
          selected
        ]}
      >
        <.icon name={icon} class="size-4" />
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ThemeToggle">
      export default {
        mounted() {
          const root = document.documentElement
          this.sync = () => {
            const choice = root.getAttribute("data-theme-choice")
            for (const button of this.el.querySelectorAll("button[data-phx-theme]")) {
              button.setAttribute("aria-pressed", String(button.dataset.phxTheme === choice))
            }
          }
          this.observer = new MutationObserver(this.sync)
          this.observer.observe(root, { attributes: true, attributeFilter: ["data-theme-choice"] })
          this.sync()
        },
        destroyed() {
          this.observer.disconnect()
        }
      }
    </script>
    """
  end

  # The logo is inlined rather than loaded with <img>, so its `currentColor`
  # wordmark follows the theme's text color. Read at compile time from the one
  # source file, without its comments.
  @logo_path Path.expand("../../../priv/static/images/logo.svg", __DIR__)
  @external_resource @logo_path
  @logo_svg @logo_path |> File.read!() |> String.replace(~r/\s*<!--.*?-->/s, "")

  @doc """
  Renders the Lanternhall logo inline, named "Lanternhall" for screen readers.
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil

  def logo(assigns) do
    assigns = assign(assigns, :svg, raw(@logo_svg))

    ~H"""
    <span id={@id} role="img" aria-label="Lanternhall" class={["block", @class]}>{@svg}</span>
    """
  end
end
