defmodule LanternhallWeb.ErrorJSON do
  @moduledoc """
  Renders the endpoint's error responses for JSON requests (`render_errors` in
  config/config.exs).

  Each body carries its status message: "404.json" renders
  `%{errors: %{detail: "Not Found"}}`.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
