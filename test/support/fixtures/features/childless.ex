defmodule Lanternhall.Fixtures.Features.Childless do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_childless

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: []

  @impl true
  def children(_config), do: []
end
