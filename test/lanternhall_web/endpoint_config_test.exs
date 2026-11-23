defmodule LanternhallWeb.EndpointConfigTest do
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../config", __DIR__)
  @repo_root Path.expand("../..", __DIR__)

  @prod_port 4321

  @prod_database "/nonexistent/lanternhall.db"

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

      test "builds URLs for http://localhost:#{port}", %{endpoint: endpoint} do
        assert endpoint[:url][:scheme] in [nil, "http"]
        assert endpoint[:url][:host] == "localhost"
        assert endpoint[:url][:port] == unquote(port)
      end

      test "accepts LiveView sockets only from http://localhost:#{port}", %{endpoint: endpoint} do
        assert endpoint[:check_origin] == ["//localhost:#{unquote(port)}"]
      end
    end
  end

  test "the running test endpoint listens on 127.0.0.1:4002 only" do
    assert LanternhallWeb.Endpoint.server_info(:http) == {:ok, {{127, 0, 0, 1}, 4002}}
  end

  # Browsers send a host's cookies to every port on it, so envs sharing a cookie name on
  # one machine would overwrite each other's session and CSRF token.
  test "dev, test and prod each name their session cookie differently", %{install: install} do
    names =
      for env <- [:dev, :test, :prod] do
        runtime_config(env, %{"LANTERNHALL_CONFIG" => install})[:lanternhall][:session_cookie]
      end

    assert Enum.all?(names, &is_binary/1)
    assert names == Enum.uniq(names)
  end

  test "prod stops when SECRET_KEY_BASE is unset", %{install: install} do
    assert_raise RuntimeError, ~r/SECRET_KEY_BASE is missing/, fn ->
      runtime_config(:prod, %{"LANTERNHALL_CONFIG" => install, "SECRET_KEY_BASE" => nil})
    end
  end

  test "prod serves HTTP when PHX_SERVER is set", %{install: install} do
    vars = %{"LANTERNHALL_CONFIG" => install, "PHX_SERVER" => "true"}
    endpoint = runtime_config(:prod, vars)[:lanternhall][LanternhallWeb.Endpoint]

    assert endpoint[:server] == true
  end

  test "prod leaves `server` unset when PHX_SERVER is unset", %{install: install} do
    vars = %{"LANTERNHALL_CONFIG" => install, "PHX_SERVER" => nil}
    endpoint = runtime_config(:prod, vars)[:lanternhall][LanternhallWeb.Endpoint]

    refute Keyword.has_key?(endpoint, :server)
  end

  describe "database" do
    test "dev, test and prod each use their own file", %{install: install} do
      databases =
        for env <- [:dev, :test, :prod] do
          config = runtime_config(env, %{"LANTERNHALL_CONFIG" => install})
          {env, config[:lanternhall][Lanternhall.Repo][:database]}
        end

      assert databases == [
               dev: Path.join(@repo_root, "lanternhall_dev.db"),
               test: Path.join(@repo_root, "lanternhall_test.db"),
               prod: @prod_database
             ]
    end

    test "the running test repo uses lanternhall_test.db" do
      assert Lanternhall.Repo.config()[:database] == Path.join(@repo_root, "lanternhall_test.db")
    end

    test "prod stops when DATABASE_PATH is unset", %{install: install} do
      assert_raise RuntimeError, ~r/DATABASE_PATH is missing/, fn ->
        runtime_config(:prod, %{"LANTERNHALL_CONFIG" => install, "DATABASE_PATH" => nil})
      end
    end
  end

  describe "env-only code" do
    test "only test compiles the fixture features' routes", %{install: install} do
      assert flag_per_env(:fixture_routes, install) == [dev: false, test: true, prod: false]
    end

    test "only dev compiles the LiveDashboard route", %{install: install} do
      assert flag_per_env(:dev_routes, install) == [dev: true, test: false, prod: false]
    end

    for app <- [:phoenix_live_dashboard, :phoenix_live_reload] do
      test "#{app} is a dev-only dependency" do
        dep = List.keyfind(Mix.Project.config()[:deps], unquote(app), 0)

        assert {_app, _version, opts} = dep
        assert opts[:only] == :dev
      end
    end

    @dev_only_keys [:code_reloader, :debug_errors, :live_reload, :watchers]

    for env <- [:test, :prod], phx_server <- [nil, "true"] do
      test "the #{env} endpoint sets no dev-only key, PHX_SERVER #{inspect(phx_server)}",
           %{install: install} do
        vars = %{"LANTERNHALL_CONFIG" => install, "PHX_SERVER" => unquote(phx_server)}
        endpoint = runtime_config(unquote(env), vars)[:lanternhall][LanternhallWeb.Endpoint]

        assert Keyword.take(endpoint, @dev_only_keys) == []
      end
    end

    test "the dev endpoint sets every dev-only key", %{install: install} do
      config = runtime_config(:dev, %{"LANTERNHALL_CONFIG" => install})
      endpoint = config[:lanternhall][LanternhallWeb.Endpoint]

      assert Enum.filter(@dev_only_keys, &endpoint[&1]) == @dev_only_keys
    end

    for env <- [:dev, :prod] do
      test "the #{env} registry holds no fixture features", %{install: install} do
        config = runtime_config(unquote(env), %{"LANTERNHALL_CONFIG" => install})

        assert config[:lanternhall][:features] == [Lanternhall.Platform.PlatformFeature]
      end
    end
  end

  describe "install config" do
    for env <- [:dev, :test], {value, state} <- [{nil, "unset"}, {"", "empty"}] do
      test "#{env} defaults to the synthetic personal example when LANTERNHALL_CONFIG is #{state}" do
        config = runtime_config(unquote(env), %{"LANTERNHALL_CONFIG" => unquote(value)})

        assert config[:lanternhall][:install].path ==
                 Path.join(@config_dir, "install/personal.example.exs")
      end
    end

    @tag :tmp_dir
    test "prod without LANTERNHALL_CONFIG reads $XDG_CONFIG_HOME/lanternhall/config.exs",
         %{install: install, tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "lanternhall", "config.exs"])
      File.mkdir_p!(Path.dirname(path))
      File.cp!(install, path)

      config = runtime_config(:prod, %{"LANTERNHALL_CONFIG" => nil, "XDG_CONFIG_HOME" => tmp_dir})

      assert %{path: ^path, kind: :work} = config[:lanternhall][:install]
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

  defp runtime_config(env, vars) do
    prod_vars = %{
      "DATABASE_PATH" => @prod_database,
      "SECRET_KEY_BASE" => "test-only"
    }

    with_env_vars(Map.merge(prod_vars, vars), fn ->
      compile_time = Config.Reader.read!(Path.join(@config_dir, "config.exs"), env: env)
      runtime = Config.Reader.read!(Path.join(@config_dir, "runtime.exs"), env: env)
      Config.Reader.merge(compile_time, runtime)
    end)
  end

  defp flag_per_env(key, install) do
    for env <- [:dev, :test, :prod] do
      config = runtime_config(env, %{"LANTERNHALL_CONFIG" => install})
      {env, config[:lanternhall][key] not in [nil, false]}
    end
  end

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
