defmodule Lanternhall.Fixtures.Features.Invalid.DuplicateCore do
  @moduledoc """
  Broken registry fixture: reuses the id of `Lanternhall.Fixtures.Features.Core`.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_core

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: []
end
