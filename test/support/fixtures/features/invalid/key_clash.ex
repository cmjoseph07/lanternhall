defmodule Lanternhall.Fixtures.Features.Invalid.KeyClash do
  @moduledoc """
  Broken registry fixture: claims a platform key and a key `:fixture_personal` owns.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_key_clash

  @impl true
  def kind, do: :work

  @impl true
  def depends_on, do: []

  @impl true
  def config_keys, do: [port: &Function.identity/1, fixture_greeting: &Function.identity/1]
end
