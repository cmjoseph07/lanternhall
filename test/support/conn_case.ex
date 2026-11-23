defmodule LanternhallWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Lanternhall.Platform.Config

  using do
    quote do
      @endpoint LanternhallWeb.Endpoint

      use LanternhallWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest, except: [build_conn: 0]
      import LanternhallWeb.ConnCase
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Lanternhall.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    {:ok, conn: build_conn()}
  end

  @doc """
  `Phoenix.ConnTest.build_conn/0` for this app: the request is for `localhost:<port>`,
  the only Host `LanternhallWeb.Plugs.HostCheck` lets through.

  `Phoenix.ConnTest.recycle/1` keeps the host but resets the port to 80, so a test that
  sends a second request on a used conn starts from `build_conn()` again instead.
  """
  def build_conn do
    %URI{host: host, port: port} = LanternhallWeb.Endpoint.struct_url()
    %{Phoenix.ConnTest.build_conn() | host: host, port: port}
  end

  def put_install(%{async: false}, fields) do
    config = Config.get()
    store_install(struct!(config, fields))
    on_exit(fn -> store_install(config) end)
  end

  defp store_install(config) do
    Application.put_env(:lanternhall, :install, config)
    Config.take_from_app_env()
  end
end
