defmodule LanternhallWeb.Platform.LandingLive do
  @moduledoc """
  Landing page served at `/` until the `home` module takes over.
  """
  use LanternhallWeb, :live_view

  alias Lanternhall.Platform.Config

  @impl true
  def mount(_params, _session, socket) do
    config = Config.get()

    {:ok,
     assign(socket,
       page_title: "Landing",
       kind: config.kind,
       module_ids: Enum.map(config.features, & &1.id()),
       version: Lanternhall.version()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>
        <Layouts.logo id="landing-logo" class="w-48" />
      </h1>
      <p class="text-base-content/70">
        <span id="install-kind" class="capitalize">{@kind}</span>
        install · Version <span id="app-version">{@version}</span>
      </p>
      <p class="text-base-content/70">
        Modules: <span id="enabled-modules" class="font-mono">{Enum.join(@module_ids, ", ")}</span>
      </p>
      <p id="home-note" class="text-base-content/70">
        Home arrives later; this landing page holds its place.
      </p>
    </Layouts.app>
    """
  end
end
