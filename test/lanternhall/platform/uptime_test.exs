defmodule Lanternhall.Platform.UptimeTest do
  use ExUnit.Case, async: false

  alias Lanternhall.Platform.Uptime

  setup do
    started_at = Uptime.started_at()
    on_exit(fn -> Uptime.mark_started(started_at) end)
  end

  test "is the wall-clock time since the marked start" do
    Uptime.mark_started(DateTime.add(DateTime.utc_now(), -75, :hour))

    assert Uptime.milliseconds() in :timer.hours(75)..(:timer.hours(75) + :timer.minutes(1))
  end

  test "is zero while the wall clock reads earlier than the start" do
    Uptime.mark_started(DateTime.add(DateTime.utc_now(), 1, :hour))

    assert Uptime.milliseconds() == 0
  end

  test "the start is a wall-clock time, never a bare clock reading" do
    assert_raise FunctionClauseError, fn ->
      Uptime.mark_started(System.monotonic_time(:millisecond))
    end
  end
end
