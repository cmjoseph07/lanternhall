defmodule LanternhallWeb.RouterTest do
  use LanternhallWeb.ConnCase, async: false

  alias Lanternhall.Platform.Features
  alias LanternhallWeb.{DisabledFeatureError, FeatureGate, Router}

  @platform_routes ~w(/ /settings /healthz)

  defp pipeline_status(verb, path) do
    conn = build_conn() |> bypass_through(Router) |> dispatch(@endpoint, verb, concrete(path))
    conn.status || 200
  rescue
    error -> Plug.Exception.status(error)
  end

  defp concrete(path), do: String.replace(path, ~r"/[:*][^/]+", "/1")

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
    sessions =
      for %{path: path, metadata: %{phoenix_live_view: {_view, _action, _opts, %{name: name}}}} <-
            Router.__routes__(),
          do: {path, name}

    assert sessions != []
    assert sessions |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1, inspect(sessions)
  end

  describe "with every feature disabled" do
    setup context do
      put_install(context, features: [])
    end

    test "the first pipeline of every route outside the platform's own refuses a feature" do
      refused =
        for route <- feature_routes(), do: {route.verb, route.path, refused_feature(route)}

      assert for({verb, path, nil} <- refused, do: {verb, path}) == []
      assert {:post, "/fixtures/core/plain", :fixture_core} in refused
      assert {:get, "/fixtures/personal", :fixture_personal} in refused
    end

    # A live navigation runs no router pipeline, so a feature's LiveView holds the gate
    # itself, as `on_mount`.
    test "every LiveView outside the platform's pages mounts the gate of its route's feature" do
      gates =
        for %{metadata: %{phoenix_live_view: {view, _action, _opts, _session}}} = route <-
              feature_routes() do
          mounted = for %{id: {FeatureGate, id}} <- view.__live__().lifecycle.mount, do: id
          {route.path, refused_feature(route), mounted}
        end

      assert for({path, feature, mounted} <- gates, mounted != [feature], do: path) == []
      assert {"/fixtures/personal", :fixture_personal, [:fixture_personal]} in gates
    end
  end

  defp feature_routes do
    Enum.reject(Router.__routes__(), &(&1.path in @platform_routes))
  end

  defp refused_feature(%{verb: verb, path: path}) do
    method = verb |> Atom.to_string() |> String.upcase()

    case Phoenix.Router.route_info(Router, method, concrete(path), "localhost") do
      %{pipe_through: [first | _]} -> refused_by(first)
      %{pipe_through: []} -> nil
    end
  end

  defp refused_by(pipeline) do
    build_conn() |> bypass_through(Router, [pipeline]) |> dispatch(@endpoint, :get, "/")
    nil
  rescue
    error in DisabledFeatureError ->
      Enum.find(Features.all(), &(DisabledFeatureError.exception(&1.id()) == error)).id()
  end
end
