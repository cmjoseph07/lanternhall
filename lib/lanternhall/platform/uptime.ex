defmodule Lanternhall.Platform.Uptime do
  @moduledoc false

  @persistent_term_key {__MODULE__, :started_at}

  @doc """
  Marks `started_at` as the moment the app started: a `System.monotonic_time/1` reading in
  milliseconds, now by default.
  """
  @spec mark_started(integer()) :: :ok
  def mark_started(started_at \\ now()),
    do: :persistent_term.put(@persistent_term_key, started_at)

  @doc "The marked start, as a `System.monotonic_time/1` reading in milliseconds."
  @spec started_at() :: integer()
  def started_at, do: :persistent_term.get(@persistent_term_key)

  @doc "The milliseconds since the app started."
  @spec milliseconds() :: integer()
  def milliseconds, do: now() - started_at()

  defp now, do: System.monotonic_time(:millisecond)
end
