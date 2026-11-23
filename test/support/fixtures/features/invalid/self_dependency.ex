defmodule Lanternhall.Fixtures.Features.Invalid.SelfDependency do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_self_dependency

  @impl true
  def kind, do: :personal

  @impl true
  def depends_on, do: [:fixture_self_dependency]

  @impl true
  def config_keys, do: []
end
