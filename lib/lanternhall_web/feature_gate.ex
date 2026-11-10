defmodule LanternhallWeb.FeatureGate do
  @moduledoc """
  The `on_mount` gate for a feature's LiveView routes (SPEC-platform.md section 3.2).

  Each feature's LiveViews sit in their own `live_session`, gated by the feature's id:

      live_session :calendar, on_mount: {LanternhallWeb.FeatureGate, :calendar} do
        live "/calendar", CalendarLive
      end

  While the feature is disabled, mount raises `LanternhallWeb.DisabledFeatureError`, which
  answers 404 exactly like a URL with no route. On the HTTP render the endpoint renders
  the 404 page. On a connected mount (an open window reconnecting after a restart that
  disabled the feature), LiveView replies "reload" for any 4xx error, and the reloaded
  page then gets the same 404.

  Plain routes of a feature use the matching plug, `LanternhallWeb.Plugs.FeatureGate`.
  """

  alias Lanternhall.Platform.Features
  alias LanternhallWeb.DisabledFeatureError

  @spec on_mount(
          Lanternhall.Platform.Feature.id(),
          map() | :not_mounted_at_router,
          map(),
          Phoenix.LiveView.Socket.t()
        ) :: {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(id, _params, _session, socket) do
    if Features.enabled?(id), do: {:cont, socket}, else: raise(DisabledFeatureError, id)
  end
end
