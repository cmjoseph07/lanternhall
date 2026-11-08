defmodule LanternhallWeb.EndpointConfigTest do
  # Not async: reading the prod runtime config needs process-wide env vars.
  use ExUnit.Case, async: false

  @config_dir Path.expand("../../config", __DIR__)

  for {env, port} <- [dev: 4000, test: 4002, prod: 4100] do
    describe "#{env} endpoint" do
      setup do
        {:ok, endpoint: endpoint_config(unquote(env))}
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

  # Reads config.exs (which imports <env>.exs) and runtime.exs exactly as
  # Mix and releases do, so the assertion covers what each env really boots with.
  defp endpoint_config(env) do
    with_prod_env_vars(fn ->
      compile_time = Config.Reader.read!(Path.join(@config_dir, "config.exs"), env: env)
      runtime = Config.Reader.read!(Path.join(@config_dir, "runtime.exs"), env: env)

      compile_time
      |> Config.Reader.merge(runtime)
      |> get_in([:lanternhall, LanternhallWeb.Endpoint])
    end)
  end

  defp with_prod_env_vars(fun) do
    vars = %{"DATABASE_PATH" => "/nonexistent/lanternhall.db", "SECRET_KEY_BASE" => "test-only"}
    previous = Map.new(vars, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(vars)

    try do
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
