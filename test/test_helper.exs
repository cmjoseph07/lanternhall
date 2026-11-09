# Real-browser tests run only when asked for: `mix test --only e2e` (or `--include e2e`).
ExUnit.start(exclude: [:e2e])
Ecto.Adapters.SQL.Sandbox.mode(Lanternhall.Repo, :manual)

# The Playwright driver needs Node and assets/node_modules, so it starts only for E2E runs.
if :e2e in ExUnit.configuration()[:include] do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  Application.put_env(:phoenix_test, :base_url, LanternhallWeb.Endpoint.url())
end
