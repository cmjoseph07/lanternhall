defmodule LanternhallWeb.DisabledFeatureError do
  @moduledoc """
  Raised by the feature route gates (`LanternhallWeb.FeatureGate` and
  `LanternhallWeb.Plugs.FeatureGate`) when a request reaches a disabled feature's route.
  """
  defexception [:message, plug_status: 404]

  @impl true
  def exception(id),
    do: %__MODULE__{message: "feature #{inspect(id)} is disabled on this install"}
end
