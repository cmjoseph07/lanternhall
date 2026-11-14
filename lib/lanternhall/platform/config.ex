defmodule Lanternhall.Platform.Config do
  @moduledoc """
  The install config: one Elixir file per install that names its kind, port, modules,
  time zone and data directory (SPEC-platform.md section 3.1).

  Features add keys of their own and are enabled through `modules`, so the file is
  checked against the feature registry (`Lanternhall.Platform.Features`) too.

  `config/runtime.exs` loads and validates it before any app starts, so a bad value
  stops boot with one line per problem. `Lanternhall.Application` then stores it once
  in `:persistent_term`, and the rest of the app reads it through `get/0`.

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
  else `~/.config/lanternhall/config.exs`. Empty or relative XDG variables are ignored.
  """
  @spec path(env()) :: {:ok, Path.t()} | {:error, [error()]}
  def path(env) do
    cond do
      present?(env["LANTERNHALL_CONFIG"]) ->
        {:ok, Path.expand(env["LANTERNHALL_CONFIG"])}

      absolute?(env["XDG_CONFIG_HOME"]) ->
        {:ok, Path.join([env["XDG_CONFIG_HOME"], "lanternhall", "config.exs"])}

      present?(env["HOME"]) ->
        {:ok, Path.join([env["HOME"], ".config", "lanternhall", "config.exs"])}

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

  @doc "Stores the validated config for the life of the node. Called once at boot."
  @spec put(t()) :: :ok
  def put(%__MODULE__{} = config), do: :persistent_term.put(@persistent_term_key, config)

  @doc "The config stored at boot."
  @spec get() :: t()
  def get, do: :persistent_term.get(@persistent_term_key)

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

  defp read_file(path) do
    {:ok, Config.Reader.read!(path)}
  rescue
    error -> {:error, [{path, "could not be read: " <> one_line(Exception.message(error))}]}
  end

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

    case {get_in(configs, [:lanternhall, :install]), others} do
      {nil, []} ->
        {:error, [{:install, "is missing; the file must set config :lanternhall, :install"}]}

      {install, []} ->
        {:ok, install}

      {_, others} ->
        {:error, others}
    end
  end

  defp validate(install, env, features) do
    if Keyword.keyword?(install) do
      validate_keys(install, env, features)
    else
      {:error, [{:install, "must be a keyword list, got #{inspect(install)}"}]}
    end
  end

  # Platform keys first. Feature keys are checked only once kind and modules give a valid
  # enabled set, because which keys exist depends on it.
  defp validate_keys(install, env, features) do
    platform = Enum.map(@known, &{&1, validate_key(&1, Keyword.get_values(install, &1), env)})
    fields = for {key, {:ok, value}} <- platform, into: %{}, do: {key, value}
    {enabled, module_errors} = enabled_features(fields, features)

    feature_keys =
      for feature <- enabled || [], {key, validator} <- feature.config_keys() do
        {key, validate_feature_key(validator, Keyword.get_values(install, key))}
      end

    errors =
      errors(platform) ++
        module_errors ++ errors(feature_keys) ++ unknown_keys(install, enabled, features)

    case errors do
      [] ->
        feature_config = Map.new(feature_keys, fn {key, {:ok, value}} -> {key, value} end)
        {:ok, Map.merge(fields, %{features: enabled, feature_config: feature_config})}

      errors ->
        {:error, errors}
    end
  end

  defp errors(results), do: for({key, {:error, reason}} <- results, do: {key, reason})

  defp enabled_features(%{kind: kind, modules: modules}, features) do
    case Features.resolve(features, kind, modules) do
      {:ok, enabled} -> {enabled, []}
      {:error, errors} -> {nil, errors}
    end
  end

  defp enabled_features(_fields, _features), do: {nil, []}

  # A key a feature owns is unknown only while that feature is disabled; with no valid
  # enabled set yet, it cannot be judged.
  defp unknown_keys(install, enabled, features) do
    owners =
      for feature <- features, {key, _} <- feature.config_keys(), into: %{}, do: {key, feature}

    for {key, _} <- Enum.uniq_by(install, &elem(&1, 0)),
        key not in @known,
        reason = unknown_key(owners[key], enabled),
        do: {key, reason}
  end

  defp unknown_key(nil, _enabled), do: "is not a known key"
  defp unknown_key(_owner, nil), do: nil

  defp unknown_key(owner, enabled) do
    if owner not in enabled, do: "belongs to #{inspect(owner.id())}, which is not enabled"
  end

  defp validate_feature_key(_validator, [_, _ | _]), do: {:error, "is set more than once"}
  defp validate_feature_key(validator, []), do: validator.(:error)
  defp validate_feature_key(validator, [value]), do: validator.({:ok, value})

  defp validate_key(_key, [_, _ | _], _env), do: {:error, "is set more than once"}
  defp validate_key(:data_dir, [], env), do: default_data_dir(env)
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
      not (is_list(modules) and Enum.all?(modules, &is_atom/1)) ->
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
    if absolute?(dir),
      do: {:ok, dir},
      else: {:error, "must be an absolute path, got #{inspect(dir)}"}
  end

  defp default_data_dir(env) do
    cond do
      absolute?(env["XDG_DATA_HOME"]) -> {:ok, Path.join(env["XDG_DATA_HOME"], "lanternhall")}
      present?(env["HOME"]) -> {:ok, Path.join([env["HOME"], ".local", "share", "lanternhall"])}
      true -> {:error, "has no default because HOME is not set; set data_dir"}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
  defp absolute?(value), do: present?(value) and Path.type(value) == :absolute
end
