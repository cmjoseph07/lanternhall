defmodule Lanternhall.Platform.Config do
  @moduledoc """
  The install config: one Elixir file per install that names its kind, port, modules,
  time zone and data directory (SPEC-platform.md section 3.1).

  `config/runtime.exs` loads and validates it before any app starts, so a bad value
  stops boot with one line per problem. `Lanternhall.Application` then stores it once
  in `:persistent_term`, and the rest of the app reads it through `get/0`.

  Problems are data until that single raise: `check/2` returns `{:error, [{key, reason}]}`,
  where `key` is the config key, or the file path for problems with the file itself.
  """

  @enforce_keys [:path, :kind, :port, :modules, :time_zone, :data_dir]
  defstruct @enforce_keys

  @type kind :: :personal | :work
  @type t :: %__MODULE__{
          path: Path.t(),
          kind: kind(),
          port: 1024..65_535,
          modules: [atom()],
          time_zone: String.t(),
          data_dir: Path.t()
        }
  @type error :: {atom() | Path.t(), String.t()}
  @type env :: %{optional(String.t()) => String.t()}

  @required [:kind, :port, :modules, :time_zone]
  @known @required ++ [:data_dir]
  @persistent_term_key {__MODULE__, :config}

  @doc """
  The config file path: `LANTERNHALL_CONFIG`, else `$XDG_CONFIG_HOME/lanternhall/config.exs`,
  else `~/.config/lanternhall/config.exs`. Empty or relative XDG variables are ignored.
  """
  @spec path(env()) :: Path.t()
  def path(env) do
    cond do
      present?(env["LANTERNHALL_CONFIG"]) ->
        Path.expand(env["LANTERNHALL_CONFIG"])

      absolute?(env["XDG_CONFIG_HOME"]) ->
        Path.join([env["XDG_CONFIG_HOME"], "lanternhall", "config.exs"])

      true ->
        Path.join([Map.fetch!(env, "HOME"), ".config", "lanternhall", "config.exs"])
    end
  end

  @doc """
  Reads and validates the config file at `path` without starting anything.
  `env` supplies `HOME` and `XDG_DATA_HOME` for the default `data_dir`.
  """
  @spec check(Path.t(), env()) :: {:ok, t()} | {:error, [error()]}
  def check(path, env) do
    with {:ok, install} <- read(path),
         {:ok, fields} <- validate(install, env) do
      {:ok, struct!(__MODULE__, Map.put(fields, :path, path))}
    end
  end

  @doc "Like `check/2`, but raises once with one line per problem."
  @spec load!(Path.t(), env()) :: t()
  def load!(path, env) do
    case check(path, env) do
      {:ok, config} -> config
      {:error, errors} -> raise format_errors(errors)
    end
  end

  @doc "Formats problems one per line, each naming the key (or file) and the reason."
  @spec format_errors([error()]) :: String.t()
  def format_errors(errors) do
    Enum.map_join(errors, "\n", fn
      {key, reason} when is_atom(key) -> "lanternhall config: #{inspect(key)} #{reason}"
      {path, reason} -> "lanternhall config: #{path} #{reason}"
    end)
  end

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

  defp validate(install, env) do
    if Keyword.keyword?(install) do
      validate_keys(install, env)
    else
      {:error, [{:install, "must be a keyword list, got #{inspect(install)}"}]}
    end
  end

  defp validate_keys(install, env) do
    results = Enum.map(@known, &{&1, validate_key(&1, Keyword.get_values(install, &1), env)})

    errors =
      for({key, {:error, reason}} <- results, do: {key, reason}) ++
        for {key, _} <- Enum.uniq_by(install, &elem(&1, 0)), key not in @known do
          {key, "is not a known key"}
        end

    case errors do
      [] -> {:ok, Map.new(results, fn {key, {:ok, value}} -> {key, value} end)}
      errors -> {:error, errors}
    end
  end

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
