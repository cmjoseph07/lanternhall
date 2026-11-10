defmodule Lanternhall.Fixtures.Features.PersonalLive do
  @moduledoc """
  LiveView route of the `:fixture_personal` feature, which the test install disables, so
  its gate answers 404 and this never renders.
  """
  use LanternhallWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 id="fixture-personal">Disabled fixture page</h1>
    </Layouts.app>
    """
  end
end
