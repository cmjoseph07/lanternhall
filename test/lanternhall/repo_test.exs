defmodule Lanternhall.RepoTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Adapters.SQLite3
  alias Exqlite.Sqlite3, as: Driver

  @moduletag :tmp_dir

  # `mix ecto.create` builds the file through storage_up/1. If that file is not
  # already in WAL mode, the migrator's pooled connections race to convert it
  # and one fails with "database is locked".
  test "a newly created database starts in WAL mode", %{tmp_dir: tmp_dir} do
    database = Path.join(tmp_dir, "new.db")
    config = Keyword.put(Lanternhall.Repo.config(), :database, database)

    assert :ok = SQLite3.storage_up(config)
    assert journal_mode(database) == "wal"
  end

  # Asked of a connection the app itself opened, so this is the mode in force, whatever
  # the config files say.
  test "the running repo is in WAL mode" do
    :ok = Sandbox.checkout(Lanternhall.Repo)

    assert %{rows: [["wal"]]} = Lanternhall.Repo.query!("PRAGMA journal_mode")
  end

  # SQLite allows one writer at a time, so a second writer has to wait for its turn
  # (SPEC.md section 5 "Data layer"). `PRAGMA busy_timeout` cannot show the setting: the
  # driver keeps the timeout in its own busy handler and the pragma reads 0. So a second
  # repo, started with the app's settings on its own file, writes while another
  # connection holds the write lock. With no timeout the write fails at once.
  test "a write waits for another connection's lock instead of failing", %{tmp_dir: tmp_dir} do
    database = Path.join(tmp_dir, "locked.db")

    repo =
      start_supervised!(
        {Lanternhall.Repo,
         name: nil, database: database, pool: DBConnection.ConnectionPool, pool_size: 1}
      )

    Lanternhall.Repo.put_dynamic_repo(repo)
    Lanternhall.Repo.query!("CREATE TABLE notes (body TEXT)")

    {:ok, locker} = Driver.open(database)
    :ok = Driver.execute(locker, "BEGIN IMMEDIATE")
    {:ok, _} = :timer.apply_after(100, Driver, :execute, [locker, "ROLLBACK"])

    assert {:ok, %{num_rows: 1}} = Lanternhall.Repo.query("INSERT INTO notes VALUES ('x')")

    :ok = Driver.close(locker)
  end

  # How long it waits is set explicitly, not left to the driver's default.
  test "the repo is given a busy timeout of 2 seconds" do
    assert Lanternhall.Repo.config()[:busy_timeout] == 2000
  end

  defp journal_mode(database) do
    {:ok, db} = Driver.open(database)
    {:ok, statement} = Driver.prepare(db, "PRAGMA journal_mode")
    {:row, [mode]} = Driver.step(db, statement)
    :ok = Driver.release(db, statement)
    :ok = Driver.close(db)
    mode
  end
end
