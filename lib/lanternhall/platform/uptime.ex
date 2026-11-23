defmodule Lanternhall.Platform.Uptime do
  @moduledoc false

  @persistent_term_key {__MODULE__, :started_at}

  @doc "Marks `started_at` as the moment the app started, now by default."
  @spec mark_started(DateTime.t()) :: :ok
  def mark_started(%DateTime{} = started_at \\ now()),
    do: :persistent_term.put(@persistent_term_key, started_at)

  @doc "The marked start."
  @spec started_at() :: DateTime.t()
  def started_at, do: :persistent_term.get(@persistent_term_key)

  @doc "The milliseconds since the app started, the time the machine slept included."
  @spec milliseconds() :: non_neg_integer()
  def milliseconds, do: max(DateTime.diff(now(), started_at(), :millisecond), 0)

  # The monotonic clock stops while the machine sleeps: :erlang.system_info(:os_monotonic_time_source).
  defp now, do: DateTime.utc_now()
end
