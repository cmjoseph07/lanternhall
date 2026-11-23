defmodule Lanternhall.Fixtures.Features.PersonalLive do
  @moduledoc false
  use LanternhallWeb, :live_view

  on_mount {LanternhallWeb.FeatureGate, :fixture_personal}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 id="fixture-personal">Disabled fixture page</h1>
    </Layouts.app>
    """
  end
end
