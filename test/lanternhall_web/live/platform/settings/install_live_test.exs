defmodule LanternhallWeb.Platform.Settings.InstallLiveTest do
  use LanternhallWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lanternhall.Platform.{Config, Uptime}
  alias LanternhallWeb.Platform.Settings.InstallLive

  describe "the page" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      {:ok, view: view, config: Config.get()}
    end

    test "is titled Settings, followed by the app name", %{view: view} do
      assert page_title(view) == "Settings · Lanternhall"
    end

    test "shows the install config stored at boot", %{view: view, config: config} do
      assert has_element?(view, "#install-kind", "personal")
      assert has_element?(view, "#install-port", "4100")
      assert has_element?(view, "#install-time-zone", config.time_zone)
      assert has_element?(view, "#install-data-dir", config.data_dir)
      assert has_element?(view, "#install-config-path", config.path)
    end

    test "lists the enabled modules: every core one plus those the config enables",
         %{view: view} do
      assert has_element?(view, "#install-modules", "platform, fixture_core")
      refute has_element?(view, "#install-modules", "fixture_personal")
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
  end

  describe "the page on a server that uses the configured port" do
    setup do
      config = Config.get()
      store(%{config | port: LanternhallWeb.Endpoint.config(:http)[:port]})
      on_exit(fn -> store(config) end)
    end

    test "shows the port without the note about another one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      assert has_element?(view, "#install-port", "4002")
      refute has_element?(view, "#install-serving-port")
    end
  end

  describe "the uptime" do
    setup do
      started_at = Uptime.started_at()
      on_exit(fn -> Uptime.mark_started(started_at) end)
    end

    test "is the time since the app started, read again on every tick", %{conn: conn} do
      Uptime.mark_started(System.monotonic_time(:millisecond))
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert has_element?(view, "#uptime", "under a minute")

      Uptime.mark_started(System.monotonic_time(:millisecond) - :timer.hours(75))
      send(view.pid, :tick)
      assert has_element?(view, "#uptime", "3 d 3 h")
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

  defp store(config) do
    Application.put_env(:lanternhall, :install, config)
    Config.take_from_app_env()
  end
end
