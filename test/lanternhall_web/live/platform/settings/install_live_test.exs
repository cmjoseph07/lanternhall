defmodule LanternhallWeb.Platform.Settings.InstallLiveTest do
  use LanternhallWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lanternhall.Platform.{Config, Uptime}

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
    setup context do
      put_install(context, port: LanternhallWeb.Endpoint.config(:http)[:port])
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
      Uptime.mark_started(DateTime.utc_now())
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert has_element?(view, "#uptime", "under a minute")

      Uptime.mark_started(DateTime.add(DateTime.utc_now(), -75, :hour))
      send(view.pid, :tick)
      assert has_element?(view, "#uptime", "3 d 3 h")
    end
  end
end
