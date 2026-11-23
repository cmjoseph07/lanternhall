defmodule Lanternhall.Platform.PlatformFeature do
  @moduledoc false
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
