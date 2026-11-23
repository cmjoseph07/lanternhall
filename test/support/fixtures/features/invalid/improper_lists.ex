defmodule Lanternhall.Fixtures.Features.Invalid.ImproperLists do
  @moduledoc false
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_improper_lists

  @impl true
  def kind, do: :personal

  @impl true
  def depends_on, do: [:fixture_core | :tail]

  @impl true
  def config_keys, do: [{:fixture_x, &Function.identity/1} | :tail]
end
