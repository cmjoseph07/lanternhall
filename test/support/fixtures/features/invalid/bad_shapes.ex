defmodule Lanternhall.Fixtures.Features.Invalid.BadShapes do
  @moduledoc """
  Broken registry fixture: implements the behaviour, but every callback returns the wrong
  shape.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: "fixture_bad_shapes"

  @impl true
  def kind, do: :home

  @impl true
  def depends_on, do: :fixture_core

  @impl true
  def config_keys, do: [fixture_bad: :not_a_function]
end
