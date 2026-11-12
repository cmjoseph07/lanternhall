defmodule LanternhallWeb do
  @moduledoc """
  What the router and every controller, component and LiveView start from:

      use LanternhallWeb, :controller
      use LanternhallWeb, :html

  Each function below returns the quoted code that `use` injects into the caller,
  so it runs once per module. Keep them to imports, uses and aliases; a function
  belongs in a module of its own, imported here.
  """

  def static_paths, do: ~w(assets images manifest.webmanifest robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import LanternhallWeb.CoreComponents

      # Common modules used in templates
      alias LanternhallWeb.Layouts
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: LanternhallWeb.Endpoint,
        router: LanternhallWeb.Router,
        statics: LanternhallWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
