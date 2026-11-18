defmodule Lanternhall.Platform.UptimeTest do
  use ExUnit.Case, async: true

  alias Lanternhall.Platform.Uptime

  test "boot marks the start: the app is no older than the node it runs on" do
    uptime = Uptime.milliseconds()
    {node_uptime, _since_last_call} = :erlang.statistics(:wall_clock)

    assert uptime in 0..node_uptime
  end
end
