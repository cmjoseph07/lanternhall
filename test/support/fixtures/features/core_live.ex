defmodule Lanternhall.Fixtures.Features.CoreLive do
  @moduledoc false
  use LanternhallWeb, :live_view

  on_mount {LanternhallWeb.FeatureGate, :fixture_core}

  @impl true
  def handle_params(%{"exit" => _}, _uri, _socket), do: exit(:fixture_exit)

  def handle_params(params, _uri, socket) do
    socket =
      if Map.has_key?(params, "flashes") do
        socket
        |> put_flash(:info, "Fixture info flash")
        |> put_flash(:error, "Fixture error flash")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 id="fixture-core">Enabled fixture page</h1>
      <.link id="to-fixture-personal" navigate={~p"/fixtures/personal"}>
        Disabled fixture page
      </.link>
    </Layouts.app>
    """
  end
end
