defmodule LanternhallWeb.DevRoutes do
  @moduledoc """
  Routes for the dev tools, compiled in dev only (config/dev.exs sets `dev_routes`).

  LiveDashboard is a dev-only dependency, so test and prod have no
  `Phoenix.LiveDashboard.Router` to import. An `if` in `LanternhallWeb.Router` cannot
  hold the import: Elixir expands both branches, and the compile would stop wherever
  the module is missing. This macro hands the router the routes in dev and nothing
  anywhere else, so the import is never expanded there.

      use LanternhallWeb.DevRoutes

  The routes pipe through the router's `:browser` pipeline, so the line goes after it.
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
