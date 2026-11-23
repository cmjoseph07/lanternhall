defmodule Lanternhall.ApplicationTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQLite3
  alias Lanternhall.Platform.Uptime

  @moduletag :tmp_dir

  @config_dir Path.expand("../../config", __DIR__)
  @boot_timeout :timer.seconds(30)

  test "booted from a release, the app migrates its database", %{tmp_dir: tmp_dir} do
    peer = boot(tmp_dir, [{~c"RELEASE_NAME", ~c"lanternhall"}])

    assert migrated?(peer)
  end

  test "booted outside a release, the app leaves its database unmigrated", %{tmp_dir: tmp_dir} do
    peer = boot(tmp_dir, [])

    refute migrated?(peer)
  end

  test "boot marks the uptime's start on the wall clock", %{tmp_dir: tmp_dir} do
    before_boot = DateTime.utc_now()
    peer = boot(tmp_dir, [])
    after_boot = DateTime.utc_now()

    started_at = :peer.call(peer, Uptime, :started_at, [])

    refute DateTime.before?(started_at, before_boot)
    refute DateTime.after?(started_at, after_boot)
  end

  defp boot(tmp_dir, os_env) do
    app_env = app_env(tmp_dir)
    :ok = SQLite3.storage_up(app_env[:lanternhall][Lanternhall.Repo])

    peer =
      start_supervised!(%{
        id: :peer,
        start: {:peer, :start_link, [%{connection: :standard_io, env: os_env}]}
      })

    :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
    :ok = :peer.call(peer, Application, :put_all_env, [app_env, [persistent: true]])

    {:ok, _apps} =
      :peer.call(peer, Application, :ensure_all_started, [:lanternhall], @boot_timeout)

    peer
  end

  defp app_env(tmp_dir) do
    [Path.join(@config_dir, "config.exs"), Path.join(@config_dir, "runtime.exs")]
    |> Enum.map(&Config.Reader.read!(&1, env: :test))
    |> Enum.reduce(&Config.Reader.merge(&2, &1))
    |> Config.Reader.merge(
      lanternhall: [
        {Lanternhall.Repo, database: Path.join(tmp_dir, "boot.db")},
        {LanternhallWeb.Endpoint, server: false}
      ]
    )
  end

  defp migrated?(peer) do
    :peer.call(peer, Ecto.Adapters.SQL, :table_exists?, [Lanternhall.Repo, "schema_migrations"])
  end
end
