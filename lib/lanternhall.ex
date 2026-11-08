defmodule Lanternhall do
  @moduledoc """
  Lanternhall keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  The running app's version, as set in `mix.exs`.
  """
  @spec version() :: String.t()
  def version, do: to_string(Application.spec(:lanternhall, :vsn))
end
