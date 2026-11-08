defmodule Lanternhall.RepoTest do
  use ExUnit.Case, async: true

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

  defp journal_mode(database) do
    {:ok, db} = Driver.open(database)
    {:ok, statement} = Driver.prepare(db, "PRAGMA journal_mode")
    {:row, [mode]} = Driver.step(db, statement)
    :ok = Driver.release(db, statement)
    :ok = Driver.close(db)
    mode
  end
end
