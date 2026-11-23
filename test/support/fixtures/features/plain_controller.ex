defmodule Lanternhall.Fixtures.Features.PlainController do
  @moduledoc false
  use LanternhallWeb, :controller

  def show(conn, _params), do: text(conn, "fixture_#{feature(conn)} plain route")

  def create(conn, _params), do: text(conn, "fixture_#{feature(conn)} plain post")

  defp feature(%Plug.Conn{path_info: [_fixtures, feature, _plain]}), do: feature
end
