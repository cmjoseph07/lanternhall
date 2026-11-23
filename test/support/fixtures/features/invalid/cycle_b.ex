defmodule Lanternhall.Fixtures.Features.Invalid.CycleB do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_cycle_b

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: [:fixture_cycle_c]

  @impl true
  def config_keys, do: []
end
