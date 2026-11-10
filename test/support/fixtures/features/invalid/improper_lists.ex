defmodule Lanternhall.Fixtures.Features.Invalid.ImproperLists do
  @moduledoc """
  Broken registry fixture: `depends_on/0` and `config_keys/0` return improper lists, which
  `Enum` functions crash on.
  """
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
