defmodule Lanternhall.Fixtures.Features.Unstartable do
  @moduledoc """
  Synthetic `:core` feature whose one child raises as it starts, as a child does when
  what it needs at boot is missing. Not in the test registry; tests pass it in directly.
  """
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
