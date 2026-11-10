defmodule LanternhallWeb.Router do
  use LanternhallWeb, :router

  # No `put_secure_browser_headers` here: LanternhallWeb.Plugs.SecurityHeaders sets the
  # CSP (with a per-request nonce) and the other security headers on every response in
  # the endpoint, before this router runs; Phoenix's default CSP would replace it.
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

  scope "/", LanternhallWeb do
    pipe_through :browser

    live "/", Platform.LandingLive
    live "/settings", Platform.Settings.InstallLive
  end

  scope "/", LanternhallWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
  end

  # Each feature's routes follow this shape (SPEC-platform.md section 3.2): one scope that
  # pipes through the feature's gate pipeline (holding `LanternhallWeb.Plugs.FeatureGate`)
  # *before* `:browser`, so a disabled feature's URL answers 404 before format negotiation
  # or the CSRF check can answer 406 or 403. Its LiveViews sit in their own `live_session`
  # gated by `LanternhallWeb.FeatureGate`, which covers connected mounts, as those never
  # pass through the router's pipelines. test/lanternhall_web/router_test.exs checks
  # every route's gates, so a gate id that names no feature fails the suite, not a
  # request. Test compiles these routes for the fixture features in
  # test/support/fixtures/features/; dev and prod never do.
  if Application.compile_env(:lanternhall, :fixture_routes, false) do
    pipeline :fixture_core_gate do
      plug LanternhallWeb.Plugs.FeatureGate, :fixture_core
    end

    pipeline :fixture_personal_gate do
      plug LanternhallWeb.Plugs.FeatureGate, :fixture_personal
    end

    scope "/fixtures/core", Lanternhall.Fixtures.Features do
      pipe_through [:fixture_core_gate, :browser]

      live_session :fixture_core, on_mount: {LanternhallWeb.FeatureGate, :fixture_core} do
        live "/", CoreLive
      end

      get "/plain", PlainController, :show
      post "/plain", PlainController, :create
    end

    scope "/fixtures/personal", Lanternhall.Fixtures.Features do
      pipe_through [:fixture_personal_gate, :browser]

      live_session :fixture_personal, on_mount: {LanternhallWeb.FeatureGate, :fixture_personal} do
        live "/", PersonalLive
      end

      get "/plain", PlainController, :show
      post "/plain", PlainController, :create
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:lanternhall, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LanternhallWeb.Telemetry
    end
  end
end
