defmodule Lanternhall.Fixtures.Features.Invalid.PersonalOnWork do
  @moduledoc """
  Broken registry fixture: a `:personal` feature depending on the `:work` feature
  `:fixture_work`.
  """
  @behaviour Lanternhall.Platform.Feature

  @impl true
  def id, do: :fixture_personal_on_work

  @impl true
  def kind, do: :personal

  @impl true
  def depends_on, do: [:fixture_work]

  @impl true
  def config_keys, do: []
end
