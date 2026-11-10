defmodule Lanternhall.Fixtures.Features.Core do
  @moduledoc """
  Synthetic `:core` feature: always enabled, supervises one child and owns an optional
  config key with a default.
  """
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
    [
      Supervisor.child_spec({Agent, fn -> config.feature_config.fixture_level end},
        id: __MODULE__
      )
    ]
  end

  defp level(:error), do: {:ok, 1}
  defp level({:ok, level}) when is_integer(level) and level > 0, do: {:ok, level}
  defp level({:ok, level}), do: {:error, "must be a positive integer, got #{inspect(level)}"}
end
