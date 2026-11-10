defmodule Lanternhall.Platform.ConfigTest do
  use ExUnit.Case, async: true

  alias Lanternhall.Platform.Config

  @moduletag :tmp_dir

  @home %{"HOME" => "/home/someone"}
  @examples_dir Path.expand("../../../config/install", __DIR__)

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
    assert {:error, errors} = tmp_dir |> write_install(install) |> Config.check(env)
    errors
  end

  describe "check/2 with a valid file" do
    test "returns the config with its path and every key", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, Keyword.put(valid_install(), :data_dir, "/srv/lanternhall"))

      assert Config.check(path, @home) ==
               {:ok,
                %Config{
                  path: path,
                  kind: :personal,
                  port: 4100,
                  modules: [],
                  time_zone: "Europe/London",
                  data_dir: "/srv/lanternhall"
                }}
    end

    test "accepts a :work install with modules listed", %{tmp_dir: tmp_dir} do
      install = Keyword.merge(valid_install(), kind: :work, modules: [:tickets, :people])

      assert {:ok, %Config{kind: :work, modules: [:tickets, :people]}} =
               tmp_dir |> write_install(install) |> Config.check(@home)
    end

    test "accepts the lowest and highest allowed ports", %{tmp_dir: tmp_dir} do
      for port <- [1024, 65_535] do
        path = write_install(tmp_dir, Keyword.put(valid_install(), :port, port))
        assert {:ok, %Config{port: ^port}} = Config.check(path, @home)
      end
    end

    test "defaults data_dir to ~/.local/share/lanternhall", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())

      assert {:ok, %Config{data_dir: "/home/someone/.local/share/lanternhall"}} =
               Config.check(path, @home)
    end

    test "defaults data_dir under an absolute XDG_DATA_HOME", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())
      env = Map.put(@home, "XDG_DATA_HOME", "/xdg/data")

      assert {:ok, %Config{data_dir: "/xdg/data/lanternhall"}} = Config.check(path, env)
    end

    test "ignores an empty or relative XDG_DATA_HOME, as the XDG spec says", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())

      for xdg <- ["", "relative/data"] do
        env = Map.put(@home, "XDG_DATA_HOME", xdg)

        assert {:ok, %Config{data_dir: "/home/someone/.local/share/lanternhall"}} =
                 Config.check(path, env)
      end
    end
  end

  describe "check/2 with the shipped examples" do
    for {file, kind} <- [{"personal.example.exs", :personal}, {"work.example.exs", :work}] do
      test "#{file} validates clean as a #{kind} install" do
        path = Path.join(@examples_dir, unquote(file))
        assert {:ok, %Config{kind: unquote(kind)}} = Config.check(path, @home)
      end
    end
  end

  describe "check/2 with a bad file" do
    test "a missing file names the path", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "missing.exs")

      assert Config.check(path, @home) ==
               {:error,
                [
                  {path,
                   "does not exist; copy config/install/personal.example.exs there or set LANTERNHALL_CONFIG"}
                ]}
    end

    test "a directory instead of a file names the path", %{tmp_dir: tmp_dir} do
      assert {:error, [{^tmp_dir, "is not a regular file"}]} = Config.check(tmp_dir, @home)
    end

    test "a syntax error gives one line naming the path and the error", %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "config :lanternhall, :install, kind:\n")

      assert {:error, [{^path, reason}]} = Config.check(path, @home)
      assert reason =~ ~r/^could not be read: .*syntax error: expression is incomplete$/
      refute reason =~ "\n"
    end

    test "a file without the install block names :install", %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "")

      assert Config.check(path, @home) ==
               {:error,
                [{:install, "is missing; the file must set config :lanternhall, :install"}]}
    end

    test "other config apps and keys are refused by name", %{tmp_dir: tmp_dir} do
      body = """
      config :lanternhall, :install, #{inspect(valid_install())}
      config :lanternhall, :repo, []
      config :logger, level: :debug
      """

      assert tmp_dir |> write_config(body) |> Config.check(@home) ==
               {:error,
                [
                  {:repo, "is not allowed; the file holds only config :lanternhall, :install"},
                  {:logger, "is not allowed; the file holds only config :lanternhall, :install"}
                ]}
    end

    test "an install block that is not a keyword list names :install", %{tmp_dir: tmp_dir} do
      path = write_config(tmp_dir, "config :lanternhall, :install, \"personal\"\n")

      assert Config.check(path, @home) ==
               {:error, [{:install, "must be a keyword list, got \"personal\""}]}
    end
  end

  describe "check/2 per key" do
    test "an unknown key is refused by name", %{tmp_dir: tmp_dir} do
      install = valid_install() ++ [modlues: [:habits]]
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
      for modules <- [:habits, ["habits"], [:habits, "learning"]] do
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

    test "data_dir has no default without HOME", %{tmp_dir: tmp_dir} do
      assert errors_for(tmp_dir, valid_install(), %{}) == [
               {:data_dir, "has no default because HOME is not set; set data_dir"}
             ]
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

  describe "path/1" do
    test "LANTERNHALL_CONFIG wins, expanded to an absolute path" do
      env = Map.merge(@home, %{"LANTERNHALL_CONFIG" => "/etc/lh.exs", "XDG_CONFIG_HOME" => "/x"})
      assert Config.path(env) == "/etc/lh.exs"

      assert Config.path(%{"LANTERNHALL_CONFIG" => "lh.exs"}) ==
               Path.join(File.cwd!(), "lh.exs")
    end

    test "then an absolute XDG_CONFIG_HOME" do
      env = Map.put(@home, "XDG_CONFIG_HOME", "/xdg/config")
      assert Config.path(env) == "/xdg/config/lanternhall/config.exs"
    end

    test "then ~/.config, ignoring empty or relative variables" do
      env = Map.merge(@home, %{"LANTERNHALL_CONFIG" => "", "XDG_CONFIG_HOME" => "rel"})
      assert Config.path(env) == "/home/someone/.config/lanternhall/config.exs"
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
    test "returns the config when the file is valid", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, valid_install())
      assert %Config{path: ^path, kind: :personal} = Config.load!(path, @home)
    end

    test "raises once with one line per problem", %{tmp_dir: tmp_dir} do
      path = write_install(tmp_dir, kind: :home, port: 1, modules: [], time_zone: "UTC")

      error = assert_raise RuntimeError, fn -> Config.load!(path, @home) end

      assert Exception.message(error) == """
             lanternhall config: :kind must be :personal or :work, got :home
             lanternhall config: :port must be an integer from 1024 to 65535, got 1\
             """
    end
  end

  describe "get/0" do
    test "returns the config stored at boot, which dev and test read from the personal example" do
      assert %Config{kind: :personal} = config = Config.get()
      assert config.path == Path.join(@examples_dir, "personal.example.exs")
    end
  end
end
