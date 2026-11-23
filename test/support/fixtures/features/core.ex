defmodule Lanternhall.Fixtures.Features.Core do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_core

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: [fixture_level: &level/1]

  @impl true
  def children(config) do
    [{Agent, fn -> config.feature_config.fixture_level end}]
  end

  defp level(:error), do: {:ok, 1}
  defp level({:ok, level}) when is_integer(level) and level > 0, do: {:ok, level}
  defp level({:ok, level}), do: {:error, "must be a positive integer, got #{inspect(level)}"}
end
