defmodule Lanternhall.Fixtures.Features.PlainController do
  @moduledoc """
  Plain (non-LiveView) GET and POST routes shared by the fixture features; the route's
  feature gate decides whether they are reached. Replies with the feature id taken from
  the path.
  """
  use LanternhallWeb, :controller

  def show(conn, _params), do: text(conn, "fixture_#{feature(conn)} plain route")

  def create(conn, _params), do: text(conn, "fixture_#{feature(conn)} plain post")

  defp feature(%Plug.Conn{path_info: [_fixtures, feature, _plain]}), do: feature
end
