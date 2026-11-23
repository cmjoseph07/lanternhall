defmodule Lanternhall.Fixtures.Features.Invalid.KeyTwice do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_key_twice

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: [fixture_twice: &__MODULE__.first/1, fixture_twice: &__MODULE__.second/1]

  def first(_fetched), do: {:ok, :first}
  def second(_fetched), do: {:ok, :second}
end
