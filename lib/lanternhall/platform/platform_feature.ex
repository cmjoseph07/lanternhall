defmodule Lanternhall.Platform.PlatformFeature do
  @moduledoc """
  Platform's own feature: always enabled, depends on nothing. Its install config keys are
  the fixed ones `Lanternhall.Platform.Config` checks itself.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :platform

  @impl true
  def kind, do: :core

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: []
end
