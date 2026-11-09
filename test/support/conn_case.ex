defmodule LanternhallWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LanternhallWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      # The default endpoint for testing
      @endpoint LanternhallWeb.Endpoint

      use LanternhallWeb, :verified_routes

      # Import conveniences for testing with connections
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
end
