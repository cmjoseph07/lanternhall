defmodule LanternhallWeb.FeatureGate do
  @moduledoc """
  The `on_mount` gate for a feature's LiveViews (SPEC-platform.md section 3.2).

  Each LiveView of a feature mounts it with the feature's id:

      defmodule LanternhallWeb.Calendar.CalendarLive do
        use LanternhallWeb, :live_view

        on_mount {LanternhallWeb.FeatureGate, :calendar}
      end

  While the feature is disabled, mount raises `LanternhallWeb.DisabledFeatureError`, which
  answers 404 exactly like a URL with no route. On the HTTP render the endpoint renders
  the 404 page. On a connected mount (a navigate into the feature, or an open window
  reconnecting after a restart that disabled it), LiveView replies "reload" for any 4xx
  error, and the page load that follows gets the same 404.
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
