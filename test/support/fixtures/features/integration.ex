defmodule Lanternhall.Fixtures.Features.Integration do
  @moduledoc """
  Synthetic `:work` feature standing in for an external integration; `:fixture_work`
  depends on it.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_integration

  @impl true
  def kind, do: :work

  @impl true
  def depends_on, do: [:fixture_core]

  @impl true
  def config_keys, do: []
end
