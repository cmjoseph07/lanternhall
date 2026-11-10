defmodule LanternhallWeb.Plugs.FeatureGate do
  @moduledoc """
  The plug gate for a feature's plain (non-LiveView) routes, matching the `on_mount` gate
  `LanternhallWeb.FeatureGate` (SPEC-platform.md section 3.2).

  A feature's plain routes pipe through a pipeline holding this plug with the feature's id:

      pipeline :calendar_gate do
        plug LanternhallWeb.Plugs.FeatureGate, :calendar
      end

  While the feature is disabled, it raises `LanternhallWeb.DisabledFeatureError`, so the
  endpoint answers 404 exactly like a URL with no route.
  """
  @behaviour Plug

  alias Lanternhall.Platform.Features
  alias LanternhallWeb.DisabledFeatureError

  @impl Plug
  def init(id) when is_atom(id), do: id

  @impl Plug
  def call(conn, id) do
    if Features.enabled?(id), do: conn, else: raise(DisabledFeatureError, id)
  end
end
