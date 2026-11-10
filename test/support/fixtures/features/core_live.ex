defmodule Lanternhall.Fixtures.Features.CoreLive do
  @moduledoc """
  LiveView route of the `:fixture_core` feature, which the test install enables. Links to
  the disabled `:fixture_personal` feature's page to prove live navigation into it.
  """
  use LanternhallWeb, :live_view

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
