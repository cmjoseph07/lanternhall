defmodule LanternhallWeb.DisabledFeatureError do
  @moduledoc """
  Raised by the feature route gates (`LanternhallWeb.FeatureGate` and
  `LanternhallWeb.Plugs.FeatureGate`) when a request reaches a disabled feature's route.

  `plug_status: 404` makes the endpoint render `LanternhallWeb.ErrorHTML`'s 404 page, the
  same reply a URL with no route gets, so a disabled feature's URLs look nonexistent
  (SPEC-platform.md section 3.2). Only the dev debug page shows this message.
  """
  defexception [:message, plug_status: 404]

  @impl true
  def exception(id),
    do: %__MODULE__{message: "feature #{inspect(id)} is disabled on this install"}
end
