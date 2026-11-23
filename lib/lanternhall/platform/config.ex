defmodule Lanternhall.Platform.Config do
  @moduledoc """
  Problems are data until that single raise: `path/1` and `check/3` return
  `{:error, [{key, reason}]}`, where `key` is the config key, the environment variable
  to set, the file path for problems with the file itself, or "the feature registry" for
  problems with the registry.
  """

  alias Lanternhall.Platform.Features

  @enforce_keys [:path, :kind, :port, :modules, :time_zone, :data_dir, :features, :feature_config]
  defstruct @enforce_keys

  @type kind :: :personal | :work
  @type t :: %__MODULE__{
          path: Path.t(),
          kind: kind(),
          port: 1024..65_535,
          modules: [atom()],
          time_zone: String.t(),
          data_dir: Path.t(),
          features: [module()],
          feature_config: %{optional(atom()) => term()}
        }
  @type error :: {atom() | String.t(), String.t()}
  @type env :: %{optional(String.t()) => String.t()}

  @required [:kind, :port, :modules, :time_zone]
  @known @required ++ [:data_dir]
  @persistent_term_key {__MODULE__, :config}

  @doc """
  The config file path: `LANTERNHALL_CONFIG`, else `$XDG_CONFIG_HOME/lanternhall/config.exs`,
  else `~/.config/lanternhall/config.exs`. Empty or relative XDG variables are ignored;
  a relative `HOME`, or a ".." segment in the variable used, is an error.
  """
  @spec path(env()) :: {:ok, Path.t()} | {:error, [error()]}
  def path(env) do
    cond do
      present?(env["LANTERNHALL_CONFIG"]) ->
        {:ok, Path.expand(env["LANTERNHALL_CONFIG"])}

      absolute?(env["XDG_CONFIG_HOME"]) ->
        default_path(env, "XDG_CONFIG_HOME", ["lanternhall", "config.exs"])

      present?(env["HOME"]) ->
        default_path(env, "HOME", [".config", "lanternhall", "config.exs"])

      true ->
        {:error,
         [{"LANTERNHALL_CONFIG", "is required because neither XDG_CONFIG_HOME nor HOME is set"}]}
    end
  end

  @doc """
  Reads and validates the config file at `path` without starting anything.
  `env` supplies `HOME` and `XDG_DATA_HOME` for the default `data_dir`; `features` is the
  registry (`Lanternhall.Platform.Features.all/0`), checked first.

  The result holds the enabled features in `features` and the values of their keys,
  as their validators returned them, in `feature_config`.
  """
  @spec check(Path.t(), env(), [module()]) :: {:ok, t()} | {:error, [error()]}
  def check(path, env, features) do
    with :ok <- Features.validate(features),
         {:ok, install} <- read(path),
         {:ok, fields} <- validate(install, env, features) do
      {:ok, struct!(__MODULE__, Map.put(fields, :path, path))}
    end
  end

  @doc """
  Boot's entry point: finds the file through `path/1`, then runs `check/3`, raising once
  with one line per problem.
  """
  @spec load!(env(), [module()]) :: t()
  def load!(env, features) do
    with {:ok, path} <- path(env),
         {:ok, config} <- check(path, env, features) do
      config
    else
      {:error, errors} -> raise format_errors(errors)
    end
  end

  @doc "Formats problems one per line, each naming the key (or file) and the reason."
  @spec format_errors([error()]) :: String.t()
  def format_errors(errors) do
    Enum.map_join(errors, "\n", fn
      {key, reason} when is_atom(key) -> "lanternhall config: #{inspect(key)} #{reason}"
      {name, reason} -> "lanternhall config: #{name} #{reason}"
    end)
  end

  @doc "The keys platform owns; features may not claim them."
  @spec platform_keys() :: [atom()]
  def platform_keys, do: @known

  @doc """
  Takes the config that `config/runtime.exs` validated out of the app env and stores it
  for the life of the node, so `get/0` is the only way to read it. Called once at boot.

  When the app is started again on the same node, the app env is already empty and the
  config stored the first time is returned.
  """
  @spec take_from_app_env() :: t()
  def take_from_app_env do
    case Application.fetch_env(:lanternhall, :install) do
      {:ok, %__MODULE__{} = config} ->
        :persistent_term.put(@persistent_term_key, config)
        Application.delete_env(:lanternhall, :install)
        config

      :error ->
        get()
    end
  end

  @doc "The config stored at boot."
  @spec get() :: t()
  def get, do: :persistent_term.get(@persistent_term_key)

  defp default_path(env, variable, rest) do
    case path_problem(env[variable]) do
      nil -> {:ok, Path.join([env[variable] | rest])}
      reason -> {:error, [{variable, reason}]}
    end
  end

  defp read(path) do
    cond do
      not File.exists?(path) ->
        {:error,
         [
           {path,
            "does not exist; copy config/install/personal.example.exs there or set LANTERNHALL_CONFIG"}
         ]}

      not File.regular?(path) ->
        {:error, [{path, "is not a regular file"}]}

      true ->
        path |> read_file() |> extract_install()
    end
  end

  # The compiler reports an undefined variable or function as a diagnostic, then raises
  # an error that says only "cannot compile file (errors have been logged)". Capturing the
  # diagnostics keeps its multi-line report off stderr and gives each error a line here.
  #
  # The file is code, so it can also throw or exit. Both are caught: an exit left alone
  # would end the caller, and Mix takes `exit({:shutdown, 0})` as success.
  defp read_file(path) do
    file = Path.expand(path)

    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          {:ok, Config.Reader.read!(path)}
        rescue
          error -> {:error, describe(error, __STACKTRACE__, file)}
        catch
          :throw, value ->
            {:error, at_frame("it threw #{inspect(value)}", __STACKTRACE__, file)}

          :exit, reason ->
            {:error, at_frame("it exited with #{inspect(reason)}", __STACKTRACE__, file)}
        end
      end)

    {compile_errors, warnings} = Enum.split_with(diagnostics, &(&1.severity == :error))
    Enum.each(warnings, &Code.print_diagnostic/1)

    case {result, compile_errors} do
      {{:ok, configs}, _} ->
        {:ok, configs}

      {{:error, reason}, []} ->
        {:error, [{path, "could not be read: " <> reason}]}

      {{:error, _reason}, compile_errors} ->
        {:error,
         for %{message: message, position: position} <- compile_errors do
           {path, "could not be read: " <> at_line(one_line(message), line(position))}
         end}
    end
  end

  defp describe(%MismatchedDelimiterError{file: file} = error, _stacktrace, file),
    do: at_line(one_line(error.description), error.end_line)

  defp describe(%type{file: file} = error, _stacktrace, file)
       when type in [SyntaxError, TokenMissingError],
       do: at_line(one_line(error.description), error.line)

  defp describe(error, stacktrace, file),
    do: at_frame(one_line(Exception.message(error)), stacktrace, file)

  defp at_frame(message, stacktrace, file) do
    line =
      Enum.find_value(stacktrace, fn entry ->
        location = elem(entry, tuple_size(entry) - 1)
        if location[:file] && Path.expand(location[:file]) == file, do: location[:line]
      end)

    at_line(message, line)
  end

  defp at_line(message, nil), do: message
  defp at_line(message, line), do: "line #{line}: #{message}"

  defp line({line, _column}), do: line
  defp line(line), do: line

  # Compiler messages span several lines with a source excerpt; keep only the prose.
  defp one_line(message) do
    message
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 =~ ~r/^(\d+\s*)?[│└┌^]/u))
    |> Enum.join(" ")
  end

  defp extract_install({:error, _} = error), do: error

  defp extract_install({:ok, configs}) do
    others =
      for {app, entries} <- configs,
          key <- if(app == :lanternhall, do: Keyword.keys(entries) -- [:install], else: [app]),
          do: {key, "is not allowed; the file holds only config :lanternhall, :install"}

    install = get_in(configs, [:lanternhall, :install])

    missing =
      if install == nil,
        do: [{:install, "is missing; the file must set config :lanternhall, :install"}],
        else: []

    case missing ++ others do
      [] -> {:ok, install}
      errors -> {:error, errors}
    end
  end

  defp validate(install, env, features) do
    if Keyword.keyword?(install) do
      validate_keys(install, env, features)
    else
      {:error, [{:install, "must be a keyword list, got #{inspect(install)}"}]}
    end
  end

  defp validate_keys(install, env, features) do
    platform = Enum.map(@known, &{&1, validate_key(&1, Keyword.get_values(install, &1), env)})
    fields = for {key, {:ok, value}} <- platform, into: %{}, do: {key, value}

    {feature_fields, feature_errors} =
      feature_fields(fields, features, Keyword.drop(install, @known))

    case errors(platform) ++ feature_errors do
      [] -> {:ok, Map.merge(fields, feature_fields)}
      errors -> {:error, errors}
    end
  end

  defp errors(results), do: for({key, {:error, reason}} <- results, do: {key, reason})

  defp feature_fields(%{kind: kind, modules: modules}, features, entries) do
    case Features.resolve(features, kind, modules) do
      {:ok, enabled} ->
        case Features.check_keys(features, enabled, entries) do
          {:ok, feature_config} -> {%{features: enabled, feature_config: feature_config}, []}
          {:error, errors} -> {%{}, errors}
        end

      {:error, errors} ->
        {%{}, errors ++ Features.unknown_keys(features, entries)}
    end
  end

  defp feature_fields(_fields, features, entries),
    do: {%{}, Features.unknown_keys(features, entries)}

  defp validate_key(_key, [_, _ | _], _env), do: {:error, "is set more than once"}

  defp validate_key(:data_dir, [], env) do
    with {:ok, dir} <- default_data_dir(env), do: validate_value(:data_dir, dir)
  end

  defp validate_key(_key, [], _env), do: {:error, "is required"}
  defp validate_key(key, [value], _env), do: validate_value(key, value)

  defp validate_value(:kind, kind) when kind in [:personal, :work], do: {:ok, kind}

  defp validate_value(:kind, kind),
    do: {:error, "must be :personal or :work, got #{inspect(kind)}"}

  defp validate_value(:port, port) when is_integer(port) and port in 1024..65_535, do: {:ok, port}

  defp validate_value(:port, port),
    do: {:error, "must be an integer from 1024 to 65535, got #{inspect(port)}"}

  defp validate_value(:modules, modules) do
    cond do
      not (is_list(modules) and not List.improper?(modules) and Enum.all?(modules, &is_atom/1)) ->
        {:error, "must be a list of module ids (atoms), got #{inspect(modules)}"}

      duplicate = List.first(modules -- Enum.uniq(modules)) ->
        {:error, "lists #{inspect(duplicate)} more than once"}

      true ->
        {:ok, modules}
    end
  end

  defp validate_value(:time_zone, zone) when is_binary(zone) do
    case DateTime.shift_zone(~U[2000-01-01 00:00:00Z], zone, Tz.TimeZoneDatabase) do
      {:ok, _} ->
        {:ok, zone}

      {:error, :time_zone_not_found} ->
        {:error, "#{inspect(zone)} is not a time zone known to tz"}
    end
  end

  defp validate_value(:time_zone, zone),
    do: {:error, "must be a time zone name such as \"Europe/London\", got #{inspect(zone)}"}

  defp validate_value(:data_dir, dir) do
    case path_problem(dir) do
      nil -> {:ok, dir}
      reason -> {:error, reason}
    end
  end

  defp default_data_dir(env) do
    cond do
      absolute?(env["XDG_DATA_HOME"]) -> {:ok, Path.join(env["XDG_DATA_HOME"], "lanternhall")}
      present?(env["HOME"]) -> {:ok, Path.join([env["HOME"], ".local", "share", "lanternhall"])}
      true -> {:error, "has no default because HOME is not set; set data_dir"}
    end
  end

  # ".." is refused, not resolved: resolving it in text can name a different directory
  # than the OS reaches when a symlink comes before it.
  defp path_problem(path) do
    cond do
      not absolute?(path) -> "must be an absolute path, got #{inspect(path)}"
      ".." in Path.split(path) -> "must not contain a \"..\" segment, got #{inspect(path)}"
      true -> nil
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
  defp absolute?(value), do: present?(value) and Path.type(value) == :absolute
end
