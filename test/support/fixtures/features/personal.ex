defmodule Lanternhall.Fixtures.Features.Personal do
  @moduledoc """
  Synthetic `:personal` feature: supervises one child and owns a required config key.
  Disabled in the test install, so it proves a disabled feature contributes nothing.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_personal

  @impl true
  def kind, do: :personal

  @impl true
  def depends_on, do: [:fixture_core]

  @impl true
  def config_keys, do: [fixture_greeting: &greeting/1]

  @impl true
  def children(config) do
    [
      Supervisor.child_spec({Agent, fn -> config.feature_config.fixture_greeting end},
        id: __MODULE__
      )
    ]
  end

  defp greeting(:error), do: {:error, "is required while :fixture_personal is enabled"}
  defp greeting({:ok, greeting}) when is_binary(greeting) and greeting != "", do: {:ok, greeting}

  defp greeting({:ok, greeting}),
    do: {:error, "must be a non-empty string, got #{inspect(greeting)}"}
end
