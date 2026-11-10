defmodule LanternhallWeb.RouterTest do
  # Feature gates check their id only when they run, so a mistyped id would surface as
  # a 500 on some later request. These walk every route so the suite catches it first.
  use LanternhallWeb.ConnCase, async: true

  alias Lanternhall.Platform.Features
  alias LanternhallWeb.{FeatureGate, Router}

  # `bypass_through/2` runs the matched route's pipelines and skips its action, so the
  # walk triggers no side effects. Path parameters get a placeholder value. A pipeline
  # that lets the request through leaves no status; that counts as 200.
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

    # Gate plugs ran: the disabled fixture feature's routes answer 404.
    assert statuses[{:get, "/fixtures/personal"}] == 404
    assert statuses[{:post, "/fixtures/personal/plain"}] == 404
  end

  test "every live_session gate names a feature" do
    ids = Enum.map(Features.all(), & &1.id())

    gates =
      for %{path: path, metadata: %{phoenix_live_view: {_, _, _, %{extra: extra}}}} <-
            Router.__routes__(),
          %{id: {FeatureGate, id}} <- Map.get(extra, :on_mount, []),
          do: {path, id}

    assert for({path, id} <- gates, id not in ids, do: {path, id}) == []
    assert {"/fixtures/personal", :fixture_personal} in gates
  end
end
