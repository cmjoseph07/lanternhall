defmodule Mix.Tasks.Lanternhall.Config.CheckTest do
  # Not async: Mix.shell/1 and the captured stderr are process-wide.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Lanternhall.Config.Check

  @moduletag :tmp_dir

  setup do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)
  end

  test "reports a valid file and returns normally" do
    path = Path.expand("../../../config/install/work.example.exs", __DIR__)

    assert Check.run([path]) == :ok
    assert_received {:mix_shell, :info, [message]}
    assert message == "lanternhall config: #{path} is valid (:work install)"
  end

  test "prints one line per problem and exits non-zero", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "config.exs")
    File.write!(path, "import Config\nconfig :lanternhall, :install, kind: :home, port: 1\n")

    assert catch_exit(Check.run([path])) == {:shutdown, 1}
    assert_received {:mix_shell, :error, [message]}

    assert message == """
           lanternhall config: :kind must be :personal or :work, got :home
           lanternhall config: :port must be an integer from 1024 to 65535, got 1
           lanternhall config: :modules is required
           lanternhall config: :time_zone is required\
           """
  end

  # What the terminal shows: the compiler's own multi-line report must not come with it.
  test "prints a compile error as its one line and nothing else", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "config.exs")
    File.write!(path, "import Config\nconfig :lanternhall, :install,\n  kind: personal\n")

    stderr = capture_io(:stderr, fn -> assert catch_exit(Check.run([path])) == {:shutdown, 1} end)

    assert stderr == ""
    assert_received {:mix_shell, :error, [message]}

    assert message ==
             ~s(lanternhall config: #{path} could not be read: line 3: undefined variable "personal")
  end

  # A warning is not a problem with the file, so it is still shown, as Elixir shows it.
  test "still shows a warning from a file that is valid", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "config.exs")

    File.write!(path, """
    import Config
    IO.warn("check this value")
    config :lanternhall, :install, kind: :personal, port: 4100, modules: [], time_zone: "UTC"
    """)

    stderr = capture_io(:stderr, fn -> assert Check.run([path]) == :ok end)

    assert stderr =~ "warning: check this value"
    assert_received {:mix_shell, :info, [message]}
    assert message == "lanternhall config: #{path} is valid (:personal install)"
  end

  test "checks modules against the feature registry", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "config.exs")

    File.write!(path, """
    import Config
    config :lanternhall, :install, kind: :personal, port: 4100, modules: [:fixture_work], time_zone: "UTC"
    """)

    assert catch_exit(Check.run([path])) == {:shutdown, 1}
    assert_received {:mix_shell, :error, [message]}

    assert message ==
             "lanternhall config: :modules contains :fixture_work, which is not allowed on a :personal install"
  end

  test "expands a relative path so the message names the real file" do
    assert catch_exit(Check.run(["no-such-config.exs"])) == {:shutdown, 1}
    assert_received {:mix_shell, :error, [message]}
    assert message =~ "lanternhall config: #{Path.expand("no-such-config.exs")} does not exist"
  end

  test "needs exactly one path" do
    for args <- [[], ["a.exs", "b.exs"]] do
      assert_raise Mix.Error, "usage: mix lanternhall.config.check <path>", fn ->
        Check.run(args)
      end
    end
  end
end
