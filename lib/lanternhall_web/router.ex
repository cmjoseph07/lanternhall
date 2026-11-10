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
