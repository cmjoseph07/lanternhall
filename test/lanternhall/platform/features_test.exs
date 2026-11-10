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

  describe "all/0" do
    test "is the :features list from config, which test extends with the fixtures" do
      assert Features.all() == @registry
    end
  end

  describe "validate/1" do
    test "accepts the registry test boots with" do
      assert Features.validate(@registry) == :ok
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
    test "collects the children of enabled features only" do
      config = config([PlatformFeature, Core], %{fixture_level: 3})

      assert [%{id: Core, start: {Agent, :start_link, [state]}}] = Features.children(config)
      assert state.() == 3
    end

    test "hands each feature the validated config" do
      config = config([Personal], %{fixture_greeting: "hello"})

      assert [%{id: Personal, start: {Agent, :start_link, [state]}}] = Features.children(config)
      assert state.() == "hello"
    end
  end

  describe "the running app" do
    test "supervises enabled features' children and not disabled ones" do
      ids =
        for {id, _pid, _type, _modules} <- Supervisor.which_children(Lanternhall.Supervisor),
            do: id

      assert Core in ids
      refute Personal in ids
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
