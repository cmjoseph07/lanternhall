defmodule Lanternhall.Fixtures.Features.Work do
  @moduledoc """
  Synthetic `:work` feature that depends on another optional feature, so enabling it alone
  proves the disabled-dependency check.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_work

  @impl true
  def kind, do: :work

  @impl true
  def depends_on, do: [:fixture_integration]

  @impl true
  def config_keys, do: []
end
