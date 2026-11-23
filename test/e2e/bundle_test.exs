defmodule LanternhallWeb.E2E.BundleTest do
  use LanternhallWeb.E2ECase

  test "an E2E run serves a bundle it built itself" do
    run_start =
      System.convert_time_unit(
        :erlang.system_info(:start_time) + :erlang.time_offset(),
        :native,
        :second
      )

    bundle = Application.app_dir(:lanternhall, "priv/static/assets/js/app.js")

    assert File.stat!(bundle, time: :posix).mtime >= run_start
  end
end
