defmodule LanternhallWeb.StaticReload do
  @moduledoc false

  import Phoenix.LiveView

  alias Phoenix.LiveView.Socket

  @spec on_mount(:default, map() | :not_mounted_at_router, map(), Socket.t()) ::
          {:cont, Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    if static_changed?(socket) do
      {:cont, attach_hook(socket, :static_reload, :handle_params, &reload/3)}
    else
      {:cont, socket}
    end
  end

  defp reload(_params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    {:halt, redirect(socket, to: URI.to_string(%URI{path: path, query: query}))}
  end
end
