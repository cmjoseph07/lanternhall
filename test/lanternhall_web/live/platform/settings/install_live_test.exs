defmodule LanternhallWeb.Platform.Settings.InstallLiveTest do
  use LanternhallWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lanternhall.Platform.Config
  alias LanternhallWeb.Platform.Settings.InstallLive

  describe "the page" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      {:ok, view: view, config: Config.get()}
    end

    test "shows the install config stored at boot", %{view: view, config: config} do
      assert has_element?(view, "#install-kind", "personal")
      assert has_element?(view, "#install-port", "4100")
      assert has_element?(view, "#install-time-zone", config.time_zone)
      assert has_element?(view, "#install-data-dir", config.data_dir)
      assert has_element?(view, "#install-config-path", config.path)
      assert has_element?(view, "#install-modules", "None")
    end

    test "notes the port this server really uses when it differs from the config", %{view: view} do
      assert has_element?(view, "#install-serving-port", "4002")
    end

    test "shows the app, Elixir, OTP, Phoenix and LiveView versions", %{view: view} do
      assert has_element?(view, "#version-app", Lanternhall.version())
      assert has_element?(view, "#version-elixir", System.version())
      assert has_element?(view, "#version-otp", System.otp_release())
      assert has_element?(view, "#version-phoenix", to_string(Application.spec(:phoenix, :vsn)))

      assert has_element?(
               view,
               "#version-live-view",
               to_string(Application.spec(:phoenix_live_view, :vsn))
             )
    end

    test "shows the uptime and keeps it current", %{view: view} do
      assert has_element?(view, "#uptime")
      send(view.pid, :tick)
      assert has_element?(view, "#uptime")
    end
  end

  describe "format_uptime/1" do
    test "reads in the largest two units" do
      assert InstallLive.format_uptime(0) == "under a minute"
      assert InstallLive.format_uptime(59_999) == "under a minute"
      assert InstallLive.format_uptime(60_000) == "1 min"
      assert InstallLive.format_uptime(:timer.minutes(59) + 59_999) == "59 min"
      assert InstallLive.format_uptime(:timer.hours(1)) == "1 h 0 min"
      assert InstallLive.format_uptime(:timer.hours(23) + :timer.minutes(5)) == "23 h 5 min"
      assert InstallLive.format_uptime(:timer.hours(24)) == "1 d 0 h"
      assert InstallLive.format_uptime(:timer.hours(24 * 9 + 3) + 1) == "9 d 3 h"
    end
  end
end
