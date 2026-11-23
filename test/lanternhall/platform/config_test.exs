defmodule Lanternhall.Platform.ConfigTest do
  use ExUnit.Case, async: true

  alias Lanternhall.Fixtures.Features.{Core, Integration, Personal, Work}
  alias Lanternhall.Platform.{Config, PlatformFeature}

  @moduletag :tmp_dir

  @home %{"HOME" => "/home/someone"}
  @examples_dir Path.expand("../../../config/install", __DIR__)
  @features [PlatformFeature, Core, Personal, Work, Integration]

  defp write_config(tmp_dir, body) do
    path = Path.join(tmp_dir, "config.exs")
    File.write!(path, "import Config\n\n" <> body)
    path
  end

  defp write_install(tmp_dir, install) do
    write_config(tmp_dir, "config :lanternhall, :install, #{inspect(install)}\n")
  end

  defp valid_install do
    [kind: :personal, port: 4100, modules: [], time_zone: "Europe/London"]
  end

  defp errors_for(tmp_dir, install, env \\ @home) do
    assert {:error, errors} = tmp_dir |> write_install(install) |> Config.check(env, @features)
    errors
  end

  describe "check/3 with a valid file" do
    test "returns the config with its path and every key", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, Keyword.put(valid_install(), :data_dir, "/srv/lanternhall"))

      assert Config.check(path, @home, @features) ==
               {:ok,
                %Config{
                  path: path,
                  kind: :personal,
                  port: 4100,
                  modules: [],
                  time_zone: "Europe/London",
                  data_dir: "/srv/lanternhall",
                  features: [PlatformFeature, Core],
                  feature_config: %{fixture_level: 1}
                }}
    end

    test "accepts a :work install with modules listed", %{tmp_dir: tmp_dir} do
      modules = [:fixture_integration, :fixture_work]
      install = Keyword.merge(valid_install(), kind: :work, modules: modules)

      assert {:ok, %Config{kind: :work, modules: ^modules, features: features}} =
               tmp_dir |> write_install(install) |> Config.check(@home, @features)

      assert features == [PlatformFeature, Core, Work, Integration]
    end

    test "passes each enabled feature's keys through its validator", %{tmp_dir: tmp_dir} do
      install =
        valid_install()
        |> Keyword.put(:modules, [:fixture_personal])
        |> Keyword.merge(fixture_level: 7, fixture_greeting: "hello")

      assert {:ok, %Config{feature_config: %{fixture_level: 7, fixture_greeting: "hello"}}} =
               tmp_dir |> write_install(install) |> Config.check(@home, @features)
    end

    test "accepts the lowest and highest allowed ports", %{tmp_dir: tmp_dir} do
      for port <- [1024, 65_535] do
        path = write_install(tmp_dir, Keyword.put(valid_install(), :port, port))
        assert {:ok, %Config{port: ^port}} = Config.check(path, @home, @features)
      end
    end

    test "defaults data_dir to ~/.local/share/lanternhall", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())

      assert {:ok, %Config{data_dir: "/home/someone/.local/share/lanternhall"}} =
               Config.check(path, @home, @features)
    end

    test "defaults data_dir under an absolute XDG_DATA_HOME", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())
      env = Map.put(@home, "XDG_DATA_HOME", "/xdg/data")

      assert {:ok, %Config{data_dir: "/xdg/data/lanternhall"}} =
               Config.check(path, env, @features)
    end

    test "ignores an empty or relative XDG_DATA_HOME, as the XDG spec says", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())

      for xdg <- ["", "relative/data"] do
        env = Map.put(@home, "XDG_DATA_HOME", xdg)

        assert {:ok, %Config{data_dir: "/home/someone/.local/share/lanternhall"}} =
                 Config.check(path, env, @features)
      end
    end
  end

  describe "check/3 with the shipped examples" do
    for {file, kind} <- [{"personal.example.exs", :personal}, {"work.example.exs", :work}] do
      test "#{file} validates clean as a #{kind} install" do
        path = Path.join(@examples_dir, unquote(file))
        assert {:ok, %Config{kind: unquote(kind)}} = Config.check(path, @home, @features)
      end
    end
  end

  describe "check/3 with a bad file" do
    test "a missing file names the path", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing.exs")

      assert Config.check(path, @home, @features) ==
               {:error,
                [
                  {path,
                   "does not exist; copy config/install/personal.example.exs there or set LANTERNHALL_CONFIG"}
                ]}
    end

    test "a directory instead of a file names the path", %{tmp_dir: tmp_dir} do
      assert {:error, [{^tmp_dir, "is not a regular file"}]} =
               Config.check(tmp_dir, @home, @features)
    end

    test "a syntax error gives one line naming the path and the error", %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "config :lanternhall, :install, kind:\n")

      assert {:error, [{^path, reason}]} = Config.check(path, @home, @features)
      assert reason =~ ~r/^could not be read: .*syntax error: expression is incomplete$/
      refute reason =~ "\n"
    end

    test "a file that raises when evaluated gives one line naming the path and the error",
         %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, ~s|System.fetch_env!("LANTERNHALL_NO_SUCH_VARIABLE")\n|)

      assert Config.check(path, @home, @features) ==
               {:error,
                [
                  {path,
                   "could not be read: could not fetch environment variable " <>
                     "\"LANTERNHALL_NO_SUCH_VARIABLE\" because it is not set"}
                ]}
    end

    test "a file that throws when evaluated gives one line naming the path and the value",
         %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "throw(:not_today)\n")

      assert Config.check(path, @home, @features) ==
               {:error, [{path, "could not be read: it threw :not_today"}]}
    end

    test "a file that exits when evaluated gives one line naming the path and the reason",
         %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "exit(:not_today)\n")

      assert Config.check(path, @home, @features) ==
               {:error, [{path, "could not be read: it exited with :not_today"}]}
    end

    # The compiler reports these as diagnostics; the exception it then raises says only
    # "cannot compile file (errors have been logged)".
    test "an atom written without its colon gives one line naming the line and the variable",
         %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "config :lanternhall, :install,\n  kind: personal\n")

      assert Config.check(path, @home, @features) ==
               {:error, [{path, ~s(could not be read: line 4: undefined variable "personal")}]}
    end

    test "a file without import Config gives one line naming the line and the call",
         %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.exs")
      File.write!(path, "config :lanternhall, :install, #{inspect(valid_install())}\n")

      assert Config.check(path, @home, @features) ==
               {:error,
                [
                  {path,
                   "could not be read: line 1: undefined function config/3 (there is no such import)"}
                ]}
    end

    # The compiler gives a position as a line or as {line, column}; code parsed with
    # columns is the way to get the second form from a config file.
    test "a compile error reported with a column still names its line", %{tmp_dir: tmp_dir} do
      body = ~s|Code.eval_quoted(Code.string_to_quoted!("personal", columns: true))\n|
      path = write_config(tmp_dir, body)

      assert Config.check(path, @home, @features) ==
               {:error, [{path, ~s(could not be read: line 1: undefined variable "personal")}]}
    end

    test "a file without the install block names :install", %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "")

      assert Config.check(path, @home, @features) ==
               {:error,
                [{:install, "is missing; the file must set config :lanternhall, :install"}]}
    end

    test "other config apps and keys are refused by name", %{tmp_dir: tmp_dir} do
      body = """
      config :lanternhall, :install, #{inspect(valid_install())}
      config :lanternhall, :repo, []
      config :logger, level: :debug
      """

      assert tmp_dir |> write_config(body) |> Config.check(@home, @features) ==
               {:error,
                [
                  {:repo, "is not allowed; the file holds only config :lanternhall, :install"},
                  {:logger, "is not allowed; the file holds only config :lanternhall, :install"}
                ]}
    end

    test "a file with other keys and no install block names both", %{tmp_dir: tmp_dir} do
      body = """
      config :lanternhall, :repo, []
      config :logger, level: :debug
      """

      assert tmp_dir |> write_config(body) |> Config.check(@home, @features) ==
               {:error,
                [
                  {:install, "is missing; the file must set config :lanternhall, :install"},
                  {:repo, "is not allowed; the file holds only config :lanternhall, :install"},
                  {:logger, "is not allowed; the file holds only config :lanternhall, :install"}
                ]}
    end

    test "an install block that is not a keyword list names :install", %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "config :lanternhall, :install, \"personal\"\n")

      assert Config.check(path, @home, @features) ==
               {:error, [{:install, "must be a keyword list, got \"personal\""}]}
    end
  end

  describe "check/3 per key" do
    test "an unknown key is refused by name", %{tmp_dir: tmp_dir} do
      install = valid_install() ++ [modlues: [:habits]]
      assert errors_for(tmp_dir, install) == [{:modlues, "is not a known key"}]
    end

    test "an unknown key written twice is named once", %{tmp_dir: tmp_dir} do
      install = valid_install() ++ [modlues: [:habits], modlues: []]
      assert errors_for(tmp_dir, install) == [{:modlues, "is not a known key"}]
    end

    test "a key set twice is refused by name", %{tmp_dir: tmp_dir} do
      install = valid_install() ++ [port: 4200]
      assert errors_for(tmp_dir, install) == [{:port, "is set more than once"}]
    end

    test "every required key is named when missing", %{tmp_dir: tmp_dir} do
      assert errors_for(tmp_dir, []) == [
               {:kind, "is required"},
               {:port, "is required"},
               {:modules, "is required"},
               {:time_zone, "is required"}
             ]
    end

    test "kind must be :personal or :work", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :kind, :home)
      assert errors_for(tmp_dir, install) == [{:kind, "must be :personal or :work, got :home"}]
    end

    test "port must be an integer from 1024 to 65535", %{tmp_dir: tmp_dir} do
      for port <- [1023, 65_536, "4100", 4100.0] do
        install = Keyword.put(valid_install(), :port, port)

        assert errors_for(tmp_dir, install) == [
                 {:port, "must be an integer from 1024 to 65535, got #{inspect(port)}"}
               ]
      end
    end

    test "modules must be a list of atoms", %{tmp_dir: tmp_dir} do
      for modules <- [:habits, ["habits"], [:habits, "learning"], [:habits | :learning]] do
        install = Keyword.put(valid_install(), :modules, modules)

        assert errors_for(tmp_dir, install) == [
                 {:modules, "must be a list of module ids (atoms), got #{inspect(modules)}"}
               ]
      end
    end

    test "modules must not list a module twice", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :modules, [:habits, :learning, :habits])
      assert errors_for(tmp_dir, install) == [{:modules, "lists :habits more than once"}]
    end

    test "time_zone must be a zone known to tz", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :time_zone, "Mars/Olympus_Mons")

      assert errors_for(tmp_dir, install) == [
               {:time_zone, "\"Mars/Olympus_Mons\" is not a time zone known to tz"}
             ]
    end

    test "time_zone must be a string", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :time_zone, :utc)

      assert errors_for(tmp_dir, install) == [
               {:time_zone, "must be a time zone name such as \"Europe/London\", got :utc"}
             ]
    end

    test "data_dir must be an absolute path", %{tmp_dir: tmp_dir} do
      for data_dir <- ["data", "~/data", :data] do
        install = Keyword.put(valid_install(), :data_dir, data_dir)

        assert errors_for(tmp_dir, install) == [
                 {:data_dir, "must be an absolute path, got #{inspect(data_dir)}"}
               ]
      end
    end

    test "data_dir must not contain a \"..\" segment", %{tmp_dir: tmp_dir} do
      for data_dir <- ["/srv/../etc", "/srv/data/..", "/../srv"] do
        install = Keyword.put(valid_install(), :data_dir, data_dir)

        assert errors_for(tmp_dir, install) == [
                 {:data_dir, "must not contain a \"..\" segment, got #{inspect(data_dir)}"}
               ]
      end
    end

    test "data_dir may have dots inside a segment's name", %{tmp_dir: tmp_dir} do
      for data_dir <- ["/srv/..data", "/srv/data..", "/srv/a..b/.hidden"] do
        path = write_install(tmp_dir, Keyword.put(valid_install(), :data_dir, data_dir))
        assert {:ok, %Config{data_dir: ^data_dir}} = Config.check(path, @home, @features)
      end
    end

    test "the default data_dir passes the same checks", %{tmp_dir: tmp_dir} do
      for {env, reason} <- [
            {Map.put(@home, "XDG_DATA_HOME", "/xdg/../data"),
             ~s(must not contain a ".." segment, got "/xdg/../data/lanternhall")},
            {%{"HOME" => "/home/../x"},
             ~s(must not contain a ".." segment, got "/home/../x/.local/share/lanternhall")},
            {%{"HOME" => "rel"}, ~s(must be an absolute path, got "rel/.local/share/lanternhall")}
          ] do
        assert errors_for(tmp_dir, valid_install(), env) == [{:data_dir, reason}]
      end
    end

    test "data_dir has no default without HOME, unset or empty", %{tmp_dir: tmp_dir} do
      for env <- [%{}, %{"HOME" => ""}] do
        assert errors_for(tmp_dir, valid_install(), env) == [
                 {:data_dir, "has no default because HOME is not set; set data_dir"}
               ]
      end
    end

    test "every problem is reported at once, in key order", %{tmp_dir: tmp_dir} do
      install = [time_zone: "Nowhere", kind: :home, port: 1, modules: [], extra: true]

      assert errors_for(tmp_dir, install) == [
               {:kind, "must be :personal or :work, got :home"},
               {:port, "must be an integer from 1024 to 65535, got 1"},
               {:time_zone, "\"Nowhere\" is not a time zone known to tz"},
               {:extra, "is not a known key"}
             ]
    end
  end

  describe "check/3 with the feature registry" do
    for {kind, module} <- [personal: :fixture_work, work: :fixture_personal] do
      test "a #{inspect(module)} module on a #{inspect(kind)} install is named with the install kind",
           %{tmp_dir: tmp_dir} do
        install = Keyword.merge(valid_install(), kind: unquote(kind), modules: [unquote(module)])

        assert errors_for(tmp_dir, install) == [
                 {:modules,
                  "contains #{inspect(unquote(module))}, which is not allowed on a " <>
                    "#{inspect(unquote(kind))} install"}
               ]
      end
    end

    test "a module whose dependency is disabled is named with the dependency",
         %{tmp_dir: tmp_dir} do
      install = Keyword.merge(valid_install(), kind: :work, modules: [:fixture_work])

      assert errors_for(tmp_dir, install) == [
               {:modules,
                "contains :fixture_work, which depends on :fixture_integration, which is not enabled"}
             ]
    end

    test "an unknown module is named", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :modules, [:habits])

      assert errors_for(tmp_dir, install) == [
               {:modules, "contains :habits, which is not a known module"}
             ]
    end

    test "an enabled feature's key is checked by that feature", %{tmp_dir: tmp_dir} do
      install = Keyword.merge(valid_install(), fixture_level: 0)

      assert errors_for(tmp_dir, install) == [
               {:fixture_level, "must be a positive integer, got 0"}
             ]
    end

    test "an enabled feature's required key is named when missing", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :modules, [:fixture_personal])

      assert errors_for(tmp_dir, install) == [
               {:fixture_greeting, "is required while :fixture_personal is enabled"}
             ]
    end

    test "an enabled feature's key set twice is refused by name", %{tmp_dir: tmp_dir} do
      install = valid_install() ++ [fixture_level: 2, fixture_level: 3]
      assert errors_for(tmp_dir, install) == [{:fixture_level, "is set more than once"}]
    end

    test "a disabled feature's key is refused, naming the feature", %{tmp_dir: tmp_dir} do
      install = valid_install() ++ [fixture_greeting: "hello"]

      assert errors_for(tmp_dir, install) == [
               {:fixture_greeting, "belongs to :fixture_personal, which is not enabled"}
             ]
    end

    test "feature keys wait until kind and modules are valid", %{tmp_dir: tmp_dir} do
      install = Keyword.put(valid_install(), :kind, :home) ++ [fixture_greeting: "hello"]

      assert errors_for(tmp_dir, install) == [
               {:kind, "must be :personal or :work, got :home"}
             ]
    end

    test "a broken registry stops the check before the file is read", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing.exs")

      assert {:error, [{"the feature registry", "gives id :fixture_core to " <> _}] = errors} =
               Config.check(path, @home, [
                 Core,
                 Lanternhall.Fixtures.Features.Invalid.DuplicateCore
               ])

      assert Config.format_errors(errors) =~
               ~r/^lanternhall config: the feature registry gives id :fixture_core to /
    end

    test "a validator that returns another shape is named as a registry problem",
         %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())
      feature = Lanternhall.Fixtures.Features.Invalid.BadValidator

      assert Config.check(path, @home, [PlatformFeature, feature]) ==
               {:error,
                [
                  {"the feature registry",
                   "has #{inspect(feature)}'s validator for :fixture_bare_ok return :ok; " <>
                     "it must return {:ok, value} or {:error, reason}, the reason a string"},
                  {"the feature registry",
                   "has #{inspect(feature)}'s validator for :fixture_atom_reason return " <>
                     "{:error, :invalid}; " <>
                     "it must return {:ok, value} or {:error, reason}, the reason a string"}
                ]}
    end
  end

  describe "path/1" do
    test "LANTERNHALL_CONFIG wins, expanded to an absolute path" do
      env = Map.merge(@home, %{"LANTERNHALL_CONFIG" => "/etc/lh.exs", "XDG_CONFIG_HOME" => "/x"})
      assert Config.path(env) == {:ok, "/etc/lh.exs"}

      assert Config.path(%{"LANTERNHALL_CONFIG" => "lh.exs"}) ==
               {:ok, Path.join(File.cwd!(), "lh.exs")}
    end

    test "then an absolute XDG_CONFIG_HOME" do
      env = Map.put(@home, "XDG_CONFIG_HOME", "/xdg/config")
      assert Config.path(env) == {:ok, "/xdg/config/lanternhall/config.exs"}
    end

    test "then ~/.config, ignoring empty or relative variables" do
      env = Map.merge(@home, %{"LANTERNHALL_CONFIG" => "", "XDG_CONFIG_HOME" => "rel"})
      assert Config.path(env) == {:ok, "/home/someone/.config/lanternhall/config.exs"}
    end

    test "refuses a relative HOME, or a \"..\" segment in the variable it would use" do
      for {env, error} <- [
            {%{"HOME" => "rel"}, {"HOME", ~s(must be an absolute path, got "rel")}},
            {%{"HOME" => "/home/../x"},
             {"HOME", ~s(must not contain a ".." segment, got "/home/../x")}},
            {Map.put(@home, "XDG_CONFIG_HOME", "/x/../y"),
             {"XDG_CONFIG_HOME", ~s(must not contain a ".." segment, got "/x/../y")}}
          ] do
        assert Config.path(env) == {:error, [error]}
      end
    end

    test "LANTERNHALL_CONFIG wins before the other variables are looked at" do
      env = %{
        "LANTERNHALL_CONFIG" => "/etc/lh.exs",
        "HOME" => "rel",
        "XDG_CONFIG_HOME" => "/x/.."
      }

      assert Config.path(env) == {:ok, "/etc/lh.exs"}
    end

    test "has no default without HOME" do
      for env <- [%{}, %{"HOME" => "", "XDG_CONFIG_HOME" => "rel"}] do
        assert Config.path(env) ==
                 {:error,
                  [
                    {"LANTERNHALL_CONFIG",
                     "is required because neither XDG_CONFIG_HOME nor HOME is set"}
                  ]}
      end
    end
  end

  describe "format_errors/1" do
    test "gives one line per problem naming the key or file and the reason" do
      errors = [{:port, "is required"}, {"/tmp/c.exs", "is not a regular file"}]

      assert Config.format_errors(errors) ==
               """
               lanternhall config: :port is required
               lanternhall config: /tmp/c.exs is not a regular file\
               """
    end
  end

  describe "load!/2" do
    test "returns the config at the path the env names", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())
      env = Map.put(@home, "LANTERNHALL_CONFIG", path)

      assert %Config{path: ^path, kind: :personal} = Config.load!(env, @features)
    end

    test "raises once with one line per problem", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, kind: :home, port: 1, modules: [], time_zone: "UTC")
      env = Map.put(@home, "LANTERNHALL_CONFIG", path)

      error = assert_raise RuntimeError, fn -> Config.load!(env, @features) end

      assert Exception.message(error) == """
             lanternhall config: :kind must be :personal or :work, got :home
             lanternhall config: :port must be an integer from 1024 to 65535, got 1\
             """
    end

    test "raises one line, without the env, when no path can be found" do
      error =
        assert_raise RuntimeError, fn -> Config.load!(%{"SECRET" => "s3cr3t"}, @features) end

      assert Exception.message(error) ==
               "lanternhall config: LANTERNHALL_CONFIG is required because neither XDG_CONFIG_HOME nor HOME is set"
    end
  end

  describe "take_from_app_env/0" do
    test "moves the config out of the app env, and returns the stored one when called again" do
      assert Application.fetch_env(:lanternhall, :install) == :error

      config = Config.get()
      Application.put_env(:lanternhall, :install, config)
      on_exit(fn -> Application.delete_env(:lanternhall, :install) end)

      assert Config.take_from_app_env() == config
      assert Application.fetch_env(:lanternhall, :install) == :error

      assert Config.take_from_app_env() == config
      assert Config.get() == config
    end
  end

  describe "get/0" do
    test "returns the config stored at boot, which dev and test read from the personal example" do
      assert %Config{kind: :personal} = config = Config.get()
      assert config.path == Path.join(@examples_dir, "personal.example.exs")
    end
  end
end
