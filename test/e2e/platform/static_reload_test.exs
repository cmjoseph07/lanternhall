defmodule LanternhallWeb.E2E.Platform.StaticReloadTest do
  use LanternhallWeb.E2ECase

  alias LanternhallWeb.ConnCase
  alias PhoenixTest.Playwright

  @moduletag :tmp_dir

  @hold_a_replaced_script_and_reconnect """
  document.documentElement.dataset.document = "old";
  document.querySelector("script[phx-track-static]").setAttribute("src", "/assets/js/app-replaced.js");
  window.liveSocket.disconnect();
  window.liveSocket.connect();
  """

  setup context do
    ConnCase.put_static_manifest(context, %{
      "assets/css/app.css" => "assets/css/app.css",
      "assets/js/app.js" => "assets/js/app.js"
    })
  end

  test "a page holding a replaced static file loads its own URL again on reconnect",
       %{conn: conn} do
    conn
    |> visit("/fixtures/core?flashes#fixture-core")
    |> assert_has("[data-phx-main].phx-connected")
    |> Playwright.evaluate(@hold_a_replaced_script_and_reconnect)
    |> refute_has("html[data-document]")
    |> assert_has("[data-phx-main].phx-connected")
    |> assert_path(~p"/fixtures/core", query_params: %{flashes: ""})
  end
end
