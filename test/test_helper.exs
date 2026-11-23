ExUnit.start(exclude: [:e2e])
Ecto.Adapters.SQL.Sandbox.mode(Lanternhall.Repo, :manual)

if :e2e in ExUnit.configuration()[:include] do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  Application.put_env(:phoenix_test, :base_url, LanternhallWeb.Endpoint.url())
end
