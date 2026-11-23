defmodule Lanternhall.Fixtures.Features.Unstartable do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_unstartable

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: []

  @impl true
  def children(_config), do: [{Agent, fn -> raise "fixture child cannot start" end}]
end
