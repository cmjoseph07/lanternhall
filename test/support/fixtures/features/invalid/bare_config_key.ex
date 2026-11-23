defmodule Lanternhall.Fixtures.Features.Invalid.BareConfigKey do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_bare_config_key

  @impl true
  def kind, do: :personal

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: [:fixture_bare]
end
