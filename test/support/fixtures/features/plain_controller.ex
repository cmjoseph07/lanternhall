defmodule Lanternhall.Fixtures.Features.PlainController do
  @moduledoc """
  Plain (non-LiveView) route shared by the fixture features; the route's feature gate
  decides whether it is reached. Replies with the feature id taken from the path.
  """
  use LanternhallWeb, :controller

  def show(conn, _params) do
    [_fixtures, feature, _plain] = conn.path_info
    text(conn, "fixture_#{feature} plain route")
  end
end
