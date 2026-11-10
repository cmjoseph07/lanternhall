defmodule Lanternhall.Fixtures.Features.CoreLive do
  @moduledoc """
  LiveView route of the `:fixture_core` feature, which the test install enables. Links to
  the disabled `:fixture_personal` feature's page to prove live navigation into it.

  With `?flashes` it shows an info and an error flash, so browser tests can measure how
  flashes render.
  """
  use LanternhallWeb, :live_view

  @impl true
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
