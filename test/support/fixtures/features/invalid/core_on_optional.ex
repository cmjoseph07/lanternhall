defmodule Lanternhall.Fixtures.Features.Invalid.CoreOnOptional do
  @moduledoc """
  Broken registry fixture: a `:core` feature that depends on an optional one.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_core_on_optional

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: [:fixture_personal]

  @impl true
  def config_keys, do: []
end
