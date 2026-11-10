defmodule LanternhallWeb.Platform.LandingLive do
  @moduledoc """
  Landing page served at `/` until the `home` module takes over.
  """
  use LanternhallWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Landing", version: Lanternhall.version())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>
        <Layouts.logo id="landing-logo" class="w-48" />
      </h1>
      <p class="text-base-content/70">
        Version <span id="app-version">{@version}</span>
      </p>
      <p id="home-note" class="text-base-content/70">
        Home arrives later; this landing page holds its place.
      </p>
    </Layouts.app>
    """
  end
end
