defmodule Lanternhall.Fixtures.Features.Invalid.UnknownDependency do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_orphan

  @impl true
  def kind, do: :personal

  @impl true
  def depends_on, do: [:fixture_missing]

  @impl true
  def config_keys, do: []
end
