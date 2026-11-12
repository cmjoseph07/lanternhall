defmodule LanternhallWeb.ErrorHTML do
  @moduledoc """
  Renders the endpoint's error pages for HTML requests (`render_errors` in
  config/config.exs).

  Each page is its status message as plain text: "404.html" renders "Not Found".
  """
  use LanternhallWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
