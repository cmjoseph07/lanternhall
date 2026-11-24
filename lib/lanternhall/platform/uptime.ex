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

  @doc """
  Formats a duration in milliseconds in its largest two units, for example `"3 d 4 h"`.
  """
  @spec format(non_neg_integer()) :: String.t()
  def format(milliseconds) do
    minutes = div(milliseconds, :timer.minutes(1))
    {hours, minutes} = {div(minutes, 60), rem(minutes, 60)}
    {days, hours} = {div(hours, 24), rem(hours, 24)}

    cond do
      days > 0 -> "#{days} d #{hours} h"
      hours > 0 -> "#{hours} h #{minutes} min"
      minutes > 0 -> "#{minutes} min"
      true -> "under a minute"
    end
  end

  # The monotonic clock stops while the machine sleeps: :erlang.system_info(:os_monotonic_time_source).
  defp now, do: DateTime.utc_now()
end
