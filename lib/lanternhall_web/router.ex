defmodule LanternhallWeb.Router do
  use LanternhallWeb, :router

  # Sobelow sees headers only in `put_secure_browser_headers` (Config.Headers) and then
  # wants a static CSP in its arguments (Config.CSP), which `merge_resp_headers` would
  # put over the per-request nonce CSP from LanternhallWeb.Plugs.SecurityHeaders.
  # sobelow_skip ["Config.Headers"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LanternhallWeb.Layouts, :root}
    plug :protect_from_forgery
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # No route sits in a `live_session` block: every LiveView is in the default one, so a
  # navigate between any two pages keeps the document. Between two `live_session`s it
  # would be a full page load.
  scope "/", LanternhallWeb do
    pipe_through :browser

    live "/", Platform.LandingLive
    live "/settings", Platform.Settings.InstallLive
  end

  scope "/", LanternhallWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
  end

  if Application.compile_env(:lanternhall, :fixture_routes, false) do
    pipeline :fixture_core_gate do
      plug LanternhallWeb.Plugs.FeatureGate, :fixture_core
    end

    pipeline :fixture_personal_gate do
      plug LanternhallWeb.Plugs.FeatureGate, :fixture_personal
    end

    scope "/fixtures/core", Lanternhall.Fixtures.Features do
      pipe_through [:fixture_core_gate, :browser]

      live "/", CoreLive

      get "/plain", PlainController, :show
      post "/plain", PlainController, :create
    end

    scope "/fixtures/personal", Lanternhall.Fixtures.Features do
      pipe_through [:fixture_personal_gate, :browser]

      live "/", PersonalLive

      get "/plain", PlainController, :show
      post "/plain", PlainController, :create
    end
  end

  use LanternhallWeb.DevRoutes
end
