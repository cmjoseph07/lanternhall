defmodule Lanternhall.Fixtures.Features.Invalid.BadValidator do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_bad_validator

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: [fixture_bare_ok: &bare_ok/1, fixture_atom_reason: &atom_reason/1]

  defp bare_ok(_fetched), do: :ok
  defp atom_reason(_fetched), do: {:error, :invalid}
end
