defmodule LanternhallWeb.RouterTest do
  use LanternhallWeb.ConnCase, async: true

  alias Lanternhall.Platform.Features
  alias LanternhallWeb.{FeatureGate, Router}

  @platform_pages ~w(/ /settings)

  defp pipeline_status(verb, path) do
    path = String.replace(path, ~r"/[:*][^/]+", "/1")
    conn = build_conn() |> bypass_through(Router) |> dispatch(@endpoint, verb, path)
    conn.status || 200
  rescue
    error -> Plug.Exception.status(error)
  end

  test "every route's pipelines run without a server error, gate plugs included" do
    statuses =
      Map.new(Router.__routes__(), &{{&1.verb, &1.path}, pipeline_status(&1.verb, &1.path)})

    assert for({route, status} <- statuses, status >= 500, do: route) == []

    assert statuses[{:get, "/fixtures/personal"}] == 404
    assert statuses[{:post, "/fixtures/personal/plain"}] == 404
  end

  test "no /dev route is compiled outside dev" do
    assert for(%{path: "/dev" <> _ = path} <- Router.__routes__(), do: path) == []
  end

  # A navigate between two `live_session`s is a full page load, so every LiveView sits
  # in the same one.
  test "every LiveView is in one live_session" do
    sessions = for {path, _view, %{name: name}} <- live_routes(), do: {path, name}

    assert sessions != []
    assert sessions |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1, inspect(sessions)
  end

  # A live navigation runs no router pipeline, so a feature's LiveView holds the gate
  # itself, as `on_mount`. The platform's own pages are the only ones without a gate.
  test "every LiveView outside the platform's pages mounts a gate that names a feature" do
    ids = Enum.map(Features.all(), & &1.id())

    gates =
      for {path, view, _session} <- live_routes(), path not in @platform_pages do
        {path, for(%{id: {FeatureGate, id}} <- view.__live__().lifecycle.mount, do: id)}
      end

    assert for({path, gate} <- gates, gate == [] or gate -- ids != [], do: path) == []
    assert {"/fixtures/personal", [:fixture_personal]} in gates
  end

  defp live_routes do
    for %{path: path, metadata: %{phoenix_live_view: {view, _action, _opts, session}}} <-
          Router.__routes__(),
        do: {path, view, session}
  end
end
