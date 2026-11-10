defmodule LanternhallWeb.EndpointConfigTest do
  # Not async: reading the runtime config needs process-wide env vars.
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../config", __DIR__)

  # Prod serves on the install config's port; this one differs from the examples' 4100.
  @prod_port 4321

  setup_all do
    install = Path.join(System.tmp_dir!(), "lanternhall-endpoint-config-test.exs")

    File.write!(install, """
    import Config

    config :lanternhall, :install,
      kind: :work, port: #{@prod_port}, modules: [], time_zone: "Etc/UTC"
    """)

    on_exit(fn -> File.rm(install) end)
    {:ok, install: install}
  end

  for {env, port} <- [dev: 4000, test: 4002, prod: @prod_port] do
    describe "#{env} endpoint" do
      setup %{install: install} do
        config = runtime_config(unquote(env), %{"LANTERNHALL_CONFIG" => install})
        {:ok, endpoint: config[:lanternhall][LanternhallWeb.Endpoint]}
      end

      test "binds to loopback only", %{endpoint: endpoint} do
        assert endpoint[:http][:ip] == {127, 0, 0, 1}
      end

      test "listens on port #{port}", %{endpoint: endpoint} do
        assert endpoint[:http][:port] == unquote(port)
      end

      test "accepts LiveView sockets only from http://localhost:#{port}", %{endpoint: endpoint} do
        assert endpoint[:check_origin] == ["//localhost:#{unquote(port)}"]
      end
    end
  end

  describe "install config" do
    for env <- [:dev, :test] do
      test "#{env} defaults to the synthetic personal example" do
        config = runtime_config(unquote(env), %{"LANTERNHALL_CONFIG" => nil})

        assert config[:lanternhall][:install].path ==
                 Path.join(@config_dir, "install/personal.example.exs")
      end
    end

    test "dev honours LANTERNHALL_CONFIG", %{install: install} do
      config = runtime_config(:dev, %{"LANTERNHALL_CONFIG" => install})
      assert %{path: ^install, kind: :work} = config[:lanternhall][:install]
    end

    test "prod stops with the problem named when the file is bad", %{install: install} do
      bad = install <> ".bad"
      File.write!(bad, "import Config\nconfig :lanternhall, :install, kind: :home\n")
      on_exit(fn -> File.rm(bad) end)

      assert_raise RuntimeError, ~r/^lanternhall config: :kind must be :personal or :work/, fn ->
        runtime_config(:prod, %{"LANTERNHALL_CONFIG" => bad})
      end
    end
  end

  # Reads config.exs (which imports <env>.exs) and runtime.exs exactly as
  # Mix and releases do, so the assertion covers what each env really boots with.
  defp runtime_config(env, vars) do
    prod_vars = %{
      "DATABASE_PATH" => "/nonexistent/lanternhall.db",
      "SECRET_KEY_BASE" => "test-only"
    }

    with_env_vars(Map.merge(prod_vars, vars), fn ->
      compile_time = Config.Reader.read!(Path.join(@config_dir, "config.exs"), env: env)
      runtime = Config.Reader.read!(Path.join(@config_dir, "runtime.exs"), env: env)
      Config.Reader.merge(compile_time, runtime)
    end)
  end

  # A nil value unsets the variable for the duration of `fun`.
  defp with_env_vars(vars, fun) do
    previous = Map.new(vars, fn {key, _} -> {key, System.get_env(key)} end)
    Enum.each(vars, &put_env/1)

    try do
      fun.()
    after
      Enum.each(previous, &put_env/1)
    end
  end

  defp put_env({key, nil}), do: System.delete_env(key)
  defp put_env({key, value}), do: System.put_env(key, value)
end
