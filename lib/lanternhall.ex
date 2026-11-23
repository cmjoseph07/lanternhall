defmodule Lanternhall do
  @moduledoc false

  @doc """
  The running app's version, as set in `mix.exs`.
  """
  @spec version() :: String.t()
  def version, do: to_string(Application.spec(:lanternhall, :vsn))
end
