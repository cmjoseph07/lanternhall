defmodule Lanternhall.Platform.FeaturesTest do
  use ExUnit.Case, async: true

  alias Lanternhall.Fixtures.Features.{Core, Integration, Invalid, Personal, Work}
  alias Lanternhall.Platform.{Config, Features, PlatformFeature}

  @registry [PlatformFeature, Core, Personal, Work, Integration]

  defp config(features, feature_config) do
    %Config{
      path: "/home/someone/.config/lanternhall/config.exs",
      kind: :personal,
      port: 4100,
      modules: [],
      time_zone: "Europe/London",
      data_dir: "/home/someone/.local/share/lanternhall",
      features: features,
      feature_config: feature_config
    }
  end

  # Stands in for Lanternhall.Supervisor, which holds the feature supervisors in the app.
  defp start_tree(config) do
    start_supervised!(%{
      id: :tree,
      start: {Supervisor, :start_link, [Features.children(config), [strategy: :one_for_one]]},
      type: :supervisor
    })
  end

  defp feature_pid(sup, id) do
    {_id, pid, :supervisor, _modules} =
      List.keyfind(Supervisor.which_children(sup), {:feature, id}, 0)

    pid
  end

  defp agent_pid(feature_sup) do
    [{Agent, pid, :worker, _}] = Supervisor.which_children(feature_sup)
    pid
  end

  defp agent_state(sup, id), do: sup |> feature_pid(id) |> agent_pid() |> Agent.get(& &1)

  defp kill_and_await(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
  end

  describe "all/0" do
    test "is the :features list from config, which test extends with the fixtures" do
      assert Features.all() == @registry
    end
  end

  describe "validate/1" do
    test "accepts the registry test boots with" do
      assert Features.validate(@registry) == :ok
    end

    test "refuses callbacks that return the wrong shape, without crashing" do
      assert Features.validate([Core, Invalid.BadShapes]) ==
               {:error,
                [
                  {:features,
                   ~s(has Lanternhall.Fixtures.Features.Invalid.BadShapes.id/0 return "fixture_bad_shapes"; it must be an atom)},
                  {:features,
                   "has Lanternhall.Fixtures.Features.Invalid.BadShapes.kind/0 return :home; it must be :core, :personal or :work"},
                  {:features,
                   "has Lanternhall.Fixtures.Features.Invalid.BadShapes.depends_on/0 return :fixture_core; it must be a list of feature ids"},
                  {:features,
                   "has Lanternhall.Fixtures.Features.Invalid.BadShapes.config_keys/0 return [fixture_bad: :not_a_function]; it must be a list of {key, validator} pairs, each key an atom and each validator a 1-arity function"}
                ]}
    end

    test "refuses improper lists from depends_on/0 and config_keys/0" do
      assert {:error, [{:features, depends_on}, {:features, config_keys}]} =
               Features.validate([Invalid.ImproperLists])

      assert depends_on =~ "depends_on/0 return [:fixture_core | :tail]; it must be a list"
      assert config_keys =~ "config_keys/0 return [{:fixture_x, &Function.identity/1} | :tail]"
    end

    test "refuses a module that does not implement the behaviour" do
      assert Features.validate([PlatformFeature, String, :no_such_module]) ==
               {:error,
                [
                  {:features,
                   "lists String, which does not implement Lanternhall.Platform.Feature"},
                  {:features,
                   "lists :no_such_module, which does not implement Lanternhall.Platform.Feature"}
                ]}
    end

    test "refuses a duplicated id, naming both modules" do
      assert Features.validate([Core, Invalid.DuplicateCore]) ==
               {:error,
                [
                  {:features,
                   "gives id :fixture_core to both Lanternhall.Fixtures.Features.Core and Lanternhall.Fixtures.Features.Invalid.DuplicateCore"}
                ]}
    end

    test "refuses a dependency on an id no feature has" do
      assert Features.validate([Core, Invalid.UnknownDependency]) ==
               {:error,
                [
                  {:features,
                   "has :fixture_orphan depend on :fixture_missing, which is not a feature"}
                ]}
    end

    test "refuses a dependency on an optional feature of another kind" do
      assert Features.validate([Core, Personal, Invalid.CoreOnOptional]) ==
               {:error,
                [
                  {:features,
                   "has :core feature :fixture_core_on_optional depend on :personal feature :fixture_personal; a feature may depend only on :core features and features of its own kind"}
                ]}
    end

    test "refuses a dependency of an optional feature on one of the other kind" do
      registry = [Core, Integration, Work, Invalid.PersonalOnWork]

      assert Features.validate(registry) ==
               {:error,
                [
                  {:features,
                   "has :personal feature :fixture_personal_on_work depend on :work feature :fixture_work; a feature may depend only on :core features and features of its own kind"}
                ]}
    end

    # The cycle sits after features with no cycle, as in a real registry, which always
    # starts with PlatformFeature.
    test "refuses a dependency cycle, naming the path" do
      assert Features.validate([
               PlatformFeature,
               Core,
               Invalid.CycleA,
               Invalid.CycleB,
               Invalid.CycleC
             ]) ==
               {:error,
                [
                  {:features,
                   "has a dependency cycle: :fixture_cycle_a -> :fixture_cycle_b -> :fixture_cycle_c -> :fixture_cycle_a"}
                ]}
    end

    test "refuses a config key that platform or another feature already owns" do
      assert Features.validate([Core, Personal, Invalid.KeyClash]) ==
               {:error,
                [
                  {:features,
                   "has :fixture_key_clash claim config key :port, which platform owns"},
                  {:features,
                   "has :fixture_key_clash claim config key :fixture_greeting, which :fixture_personal owns"}
                ]}
    end
  end

  describe "resolve/3" do
    test "enables every :core feature plus the listed modules, in registry order" do
      assert Features.resolve(@registry, :work, [:fixture_work, :fixture_integration]) ==
               {:ok, [PlatformFeature, Core, Work, Integration]}

      assert Features.resolve(@registry, :personal, []) == {:ok, [PlatformFeature, Core]}
    end

    test "refuses an unknown module" do
      assert Features.resolve(@registry, :personal, [:habits]) ==
               {:error, [{:modules, "contains :habits, which is not a known module"}]}
    end

    test "refuses a core module, which is always enabled" do
      assert Features.resolve(@registry, :personal, [:fixture_core]) ==
               {:error,
                [{:modules, "contains :fixture_core, which is a core module and always enabled"}]}
    end

    test "refuses a module on the wrong kind of install" do
      assert Features.resolve(@registry, :personal, [:fixture_work]) ==
               {:error,
                [
                  {:modules,
                   "contains :fixture_work, which is not allowed on a :personal install"}
                ]}
    end

    test "refuses a module whose dependency is not enabled" do
      assert Features.resolve(@registry, :work, [:fixture_work]) ==
               {:error,
                [
                  {:modules,
                   "contains :fixture_work, which depends on :fixture_integration, which is not enabled"}
                ]}
    end

    test "reports every problem at once, in the order listed" do
      assert {:error, [{:modules, first}, {:modules, second}]} =
               Features.resolve(@registry, :work, [:habits, :fixture_personal])

      assert first =~ ":habits"
      assert second =~ ":fixture_personal"
    end
  end

  describe "children/1" do
    test "gives each enabled feature with children its own supervisor" do
      config = config([PlatformFeature, Core], %{fixture_level: 3})

      assert [
               %{
                 id: {:feature, :fixture_core},
                 start: {Supervisor, :start_link, [[{Agent, state}], [strategy: :one_for_one]]},
                 type: :supervisor,
                 restart: :transient
               }
             ] = Features.children(config)

      assert state.() == 3
    end

    test "hands each feature the validated config" do
      config = config([Personal], %{fixture_greeting: "hello"})

      assert [%{start: {Supervisor, :start_link, [[{Agent, state}], _opts]}}] =
               Features.children(config)

      assert state.() == "hello"
    end

    test "starts features whose children share a child id" do
      config = config([Core, Personal], %{fixture_level: 3, fixture_greeting: "hello"})
      sup = start_tree(config)

      assert [Core, Personal] |> Enum.map(&agent_state(sup, &1.id())) == [3, "hello"]
    end

    test "stops a feature whose child keeps crashing and leaves the others running" do
      config = config([Core, Personal], %{fixture_level: 3, fixture_greeting: "hello"})
      sup = start_tree(config)
      feature_sup = feature_pid(sup, :fixture_core)
      ref = Process.monitor(feature_sup)

      # The default restart intensity allows 3 restarts in 5 seconds; the 4th crash ends it.
      ExUnit.CaptureLog.capture_log(fn ->
        for _ <- 1..4, do: kill_and_await(agent_pid(feature_sup))
        assert_receive {:DOWN, ^ref, :process, ^feature_sup, :shutdown}
      end)

      assert feature_pid(sup, :fixture_core) == :undefined
      assert agent_state(sup, :fixture_personal) == "hello"
    end
  end

  describe "the running app" do
    test "supervises enabled features and not disabled ones" do
      ids =
        for {id, _pid, _type, _modules} <- Supervisor.which_children(Lanternhall.Supervisor),
            do: id

      assert {:feature, :fixture_core} in ids
      refute {:feature, :fixture_personal} in ids
    end

    test "boots with the test install's enabled set" do
      assert Config.get().features == [PlatformFeature, Core]
    end
  end

  describe "enabled?/1" do
    test "is true for a feature in the enabled set stored at boot" do
      assert Features.enabled?(:fixture_core)
    end

    test "is false for a known feature the install leaves disabled" do
      refute Features.enabled?(:fixture_personal)
    end

    test "raises for an id no feature has, so a mistyped route gate fails loudly" do
      assert_raise ArgumentError, "no feature has id :fixture_typo", fn ->
        Features.enabled?(:fixture_typo)
      end
    end
  end

  describe "the composition root" do
    test "is the only place that names a feature module; compiled app code never does" do
      features = Features.all()

      ebin = Application.app_dir(:lanternhall, "ebin")

      # Read the .beam files on disk: under `mix test --cover` loaded modules have none.
      for module <- Application.spec(:lanternhall, :modules), module not in features do
        beam = to_charlist(Path.join(ebin, "#{module}.beam"))
        {:ok, {^module, [atoms: atoms]}} = :beam_lib.chunks(beam, [:atoms])
        named = for {_index, atom} <- atoms, atom in features, do: atom

        assert named == [],
               "#{inspect(module)} names #{inspect(named)}; read the registry instead"
      end
    end
  end
end
