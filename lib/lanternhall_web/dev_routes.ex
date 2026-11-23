defmodule LanternhallWeb.DevRoutes do
  @moduledoc """
  LiveDashboard is a dev-only dependency, so test and prod have no
  `Phoenix.LiveDashboard.Router` to import. An `if` in `LanternhallWeb.Router` cannot
  hold the import: Elixir expands both branches, and the compile would stop wherever
  the module is missing. This macro hands the router the routes in dev and nothing
  anywhere else, so the import is never expanded there.
  """

  if Application.compile_env(:lanternhall, :dev_routes) do
    defmacro __using__(_opts) do
      quote do
        import Phoenix.LiveDashboard.Router

        scope "/dev" do
          pipe_through :browser

          live_dashboard "/dashboard", metrics: LanternhallWeb.Telemetry
        end
      end
    end
  else
    defmacro __using__(_opts), do: nil
  end
end
