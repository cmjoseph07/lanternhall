defmodule Mix.Tasks.Lanternhall.Tailwind.InstallTest do
  # Not async: Mix.shell/1 and the :tailwind and :lanternhall app env are process-wide.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Lanternhall.Tailwind.Install

  @moduletag :tmp_dir

  @repo_root Path.expand("../../..", __DIR__)

  # Stands in for the Tailwind binary: it writes its arguments next to itself, so a test
  # can tell whether it ran.
  @pinned_binary """
  #!/bin/sh
  echo "$@" > "$0.ran"
  """

  @forged_binary @pinned_binary <> "# forged\n"

  # The binary lives in the test's own directory and the pin is the stand-in's hash, so
  # no test touches the real binary in _build or reaches GitHub.
  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "tailwind")
    put_env(:tailwind, :path, path)

    put_env(:lanternhall, :tailwind_sha256, %{
      Tailwind.configured_target() => sha256(@pinned_binary)
    })

    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)

    {:ok, path: path}
  end

  defp put_env(app, key, value) do
    previous = Application.fetch_env(app, key)
    Application.put_env(app, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(app, key, value)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  # Serves `bytes` for every request on a free loopback port and returns the base URL to
  # install from. The test process gets a message for each download.
  defp serve(bytes) do
    test = self()

    plug = fn conn, _opts ->
      send(test, {:downloaded, conn.request_path})
      Plug.Conn.send_resp(conn, 200, bytes)
    end

    server =
      start_supervised!({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    "http://127.0.0.1:#{port}/v$version/tailwindcss-$target"
  end

  defp install_binary(path, bytes) do
    File.write!(path, bytes)
    File.chmod!(path, 0o755)
  end

  describe "run/1" do
    test "downloads a missing binary for this version and platform", %{path: path} do
      assert Install.run([serve(@pinned_binary)]) == :ok

      expected = "/v#{Tailwind.configured_version()}/tailwindcss-#{Tailwind.configured_target()}"
      assert_received {:downloaded, ^expected}
      refute_received {:mix_shell, :info, _message}
      assert File.read!(path) == @pinned_binary
      assert Bitwise.band(File.stat!(path).mode, 0o111) == 0o111
    end

    test "keeps a binary with the pinned hash: no download, and the binary is not run",
         %{path: path} do
      install_binary(path, @pinned_binary)

      assert Install.run([serve(@forged_binary)]) == :ok

      refute_received {:downloaded, _path}
      assert File.read!(path) == @pinned_binary
      refute File.exists?(path <> ".ran")
    end

    test "replaces a binary with another hash and says so, without running it",
         %{path: path} do
      install_binary(path, @forged_binary)

      assert Install.run([serve(@pinned_binary)]) == :ok

      assert_received {:downloaded, _path}
      assert_received {:mix_shell, :info, [message]}
      assert message == "The Tailwind binary at #{path} is not the pinned one; replacing it"
      assert File.read!(path) == @pinned_binary
      refute File.exists?(path <> ".ran")
    end

    test "deletes a download with another hash and fails, naming both hashes", %{path: path} do
      error = assert_raise Mix.Error, fn -> Install.run([serve(@forged_binary)]) end

      assert error.message =~ "is not the pinned one, and was deleted"
      assert error.message =~ "downloaded SHA-256: #{sha256(@forged_binary)}"
      assert error.message =~ "pinned SHA-256:     #{sha256(@pinned_binary)}"
      assert error.message =~ ":tailwind_sha256 in config/config.exs"
      refute File.exists?(path)
      refute File.exists?(path <> ".ran")
    end

    test "fails before any download on a platform with no pinned hash", %{path: path} do
      Application.put_env(:lanternhall, :tailwind_sha256, %{"plan9-x64" => sha256(@pinned_binary)})

      error = assert_raise Mix.Error, fn -> Install.run([serve(@pinned_binary)]) end

      assert error.message =~ "No SHA-256 is pinned"
      assert error.message =~ "(#{Tailwind.configured_target()})"
      refute_received {:downloaded, _path}
      refute File.exists?(path)
    end

    test "refuses more than one argument" do
      assert_raise Mix.Error, "usage: mix lanternhall.tailwind.install [BASE_URL]", fn ->
        Install.run(["one", "two"])
      end
    end
  end

  describe "install_and_run/2" do
    test "runs the pinned binary with the profile's arguments and the given ones",
         %{path: path} do
      install_binary(path, @pinned_binary)

      capture_io(fn -> assert Install.install_and_run(:lanternhall, ["--watch"]) == 0 end)

      assert File.read!(path <> ".ran") =~ ~r/^--input=assets\/css\/app\.css .* --watch$/
    end

    # The default URL is GitHub's, so the refusal is reached through a platform with no
    # pin, which fails before any download.
    test "reports a failed check and returns without running Tailwind", %{path: path} do
      install_binary(path, @pinned_binary)
      Application.put_env(:lanternhall, :tailwind_sha256, %{})

      assert Install.install_and_run(:lanternhall, ["--watch"]) == :error

      assert_received {:mix_shell, :error, [message]}
      assert message =~ "No SHA-256 is pinned"
      refute File.exists?(path <> ".ran")
    end
  end

  # The task protects nothing unless every way the project runs Tailwind goes through it.
  # These read the config files and aliases as written, not the app env set up above.
  describe "the project" do
    test "pins a SHA-256 for each platform mise.lock covers" do
      pins = config(:test)[:lanternhall][:tailwind_sha256]

      locked =
        ~r/"platforms\.([a-z0-9-]+)"/
        |> Regex.scan(File.read!(Path.join(@repo_root, "mise.lock")), capture: :all_but_first)
        |> List.flatten()
        |> Enum.uniq()

      assert Enum.sort(Map.keys(pins)) == Enum.sort(locked)
      for {_target, sha256} <- pins, do: assert(sha256 =~ ~r/^[0-9a-f]{64}$/)
    end

    test "every alias that runs Tailwind checks the binary first" do
      aliases = Mix.Project.config()[:aliases]

      for name <- [:"assets.build", :"assets.deploy"] do
        steps = aliases[name]
        check = Enum.find_index(steps, &(&1 == "lanternhall.tailwind.install"))
        run = Enum.find_index(steps, &String.starts_with?(&1, "tailwind "))

        assert is_integer(check) and is_integer(run) and check < run,
               "#{name} runs Tailwind before lanternhall.tailwind.install: #{inspect(steps)}"
      end
    end

    test "assets.setup installs Tailwind through the check, never the package's installer" do
      steps = Mix.Project.config()[:aliases][:"assets.setup"]

      assert "lanternhall.tailwind.install" in steps
      refute Enum.any?(steps, &String.starts_with?(&1, "tailwind.install"))
    end

    test "the dev watcher runs Tailwind through the check" do
      watchers = config(:dev)[:lanternhall][LanternhallWeb.Endpoint][:watchers]

      assert {Install, :install_and_run, [:lanternhall, ["--watch"]]} = watchers[:tailwind]
    end

    # With its version check on, the tailwind app runs the binary (`--help`) when it
    # starts, which in dev is before the watcher's check.
    test "no env lets the tailwind app run the binary when it starts" do
      for env <- [:dev, :test, :prod] do
        assert config(env)[:tailwind][:version_check] == false
      end
    end
  end

  defp config(env) do
    Config.Reader.read!(Path.join(@repo_root, "config/config.exs"), env: env)
  end
end
