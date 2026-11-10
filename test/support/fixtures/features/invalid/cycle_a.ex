defmodule Lanternhall.Fixtures.Features.Invalid.CycleA do
  @moduledoc """
  Broken registry fixture: depends on `:fixture_cycle_b`, which depends back on it.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_cycle_a

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: [:fixture_cycle_b]

  @impl true
  def config_keys, do: []
end
