defmodule Lanternhall.Platform.Features do
  @moduledoc """
  Problems are data, like the config's own: `{"the feature registry", reason}` for a broken
  registry (a code problem, so it is named as the registry and not as an install key),
  `{:modules, reason}` for an install that enables the wrong modules and `{key, reason}`
  for an install key outside the platform's own.
  """

  alias Lanternhall.Platform.{Config, Feature}

  require Logger

  @registry "the feature registry"

  @doc "Every feature implementation, in the order `config/config.exs` lists them."
  @spec all() :: [module()]
  def all, do: Application.fetch_env!(:lanternhall, :features)

  @doc """
  Checks the registry itself: each entry implements the behaviour and its callbacks
  return the shapes the behaviour names, ids are unique, dependencies exist, are `:core`
  or of the dependent's kind and form no cycle, and no two owners claim the same install
  config key.
  """
  @spec validate([module()]) :: :ok | {:error, [Config.error()]}
  def validate(features) do
    problems =
      with [] <- not_features(features),
           [] <- Enum.flat_map(features, &shape_problems/1) do
        by_id = Map.new(features, &{&1.id(), &1})

        duplicate_ids(features) ++
          dependency_problems(features, by_id) ++ cycle(features) ++ key_clashes(features)
      end

    case problems do
      [] -> :ok
      problems -> {:error, Enum.map(problems, &{@registry, &1})}
    end
  end

  @doc """
  The enabled set for an install of `kind` listing `modules`: every `:core` feature plus
  the listed ones, in registry order. Each listed id must be a known optional feature
  allowed on `kind`, with its dependencies enabled. Expects a registry that passed
  `validate/1`.
  """
  @spec resolve([module()], Config.kind(), [Feature.id()]) ::
          {:ok, [module()]} | {:error, [Config.error()]}
  def resolve(features, kind, modules) do
    by_id = Map.new(features, &{&1.id(), &1})

    errors =
      for id <- modules, reason = module_problem(by_id[id], kind, modules, by_id) do
        {:modules, "contains #{inspect(id)}, which #{reason}"}
      end

    case errors do
      [] -> {:ok, Enum.filter(features, &core_or_listed?(&1, modules))}
      errors -> {:error, errors}
    end
  end

  @doc """
  Checks `entries`, the install's entries outside the platform's own keys, against the
  `enabled` set `resolve/3` returned: each enabled feature's validators run on its keys,
  and a key of no feature, or of a feature that is not enabled, is refused. Returns the
  validators' values by key.

  A validator that returns a shape the behaviour does not name is a registry problem that
  only running it shows, so it is reported here and not by `validate/1`.
  """
  @spec check_keys([module()], [module()], keyword()) ::
          {:ok, %{optional(atom()) => term()}} | {:error, [Config.error()]}
  def check_keys(features, enabled, entries) do
    results =
      for feature <- enabled, {key, validator} <- feature.config_keys() do
        {key, feature, run_validator(validator, Keyword.get_values(entries, key))}
      end

    case Enum.flat_map(results, &validator_error/1) ++ stray_keys(features, enabled, entries) do
      [] -> {:ok, Map.new(results, fn {key, _feature, {:ok, value}} -> {key, value} end)}
      errors -> {:error, errors}
    end
  end

  @doc """
  The problems of `entries` that need no enabled set: the keys no feature in the registry
  owns. `check_keys/3` reports them too.
  """
  @spec unknown_keys([module()], keyword()) :: [Config.error()]
  def unknown_keys(features, entries), do: stray_keys(features, features, entries)

  @doc """
  Whether feature `id` is in the enabled set stored at boot. Raises for an id no feature
  has, so a mistyped route gate fails loudly instead of quietly answering 404.
  """
  @spec enabled?(Feature.id()) :: boolean()
  def enabled?(id) do
    cond do
      Enum.any?(Config.get().features, &(&1.id() == id)) -> true
      Enum.any?(all(), &(&1.id() == id)) -> false
      true -> raise ArgumentError, "no feature has id #{inspect(id)}"
    end
  end

  @doc """
  One supervisor per enabled feature with children, in registry order, with id
  `{:feature, id}`. Child ids then only need to be unique within their feature.

  A feature stops alone, and the rest of the app keeps running:

    * if a child fails to start, the feature is logged and left stopped (see
      `start_feature/2`), so the app boots without it;
    * if a child crashes past the supervisor's restart limit, the feature stops and is
      not started again, as each supervisor is `:transient`.
  """
  @spec children(Config.t()) :: [Supervisor.child_spec()]
  def children(%Config{features: features} = config) do
    for feature <- features,
        implements?(feature, :children, 1),
        children = feature.children(config),
        children != [] do
      %{
        id: {:feature, feature.id()},
        start: {__MODULE__, :start_feature, [feature.id(), children]},
        type: :supervisor,
        restart: :transient
      }
    end
  end

  @doc """
  Starts the supervisor of feature `id` over `children`; the start function of the child
  specs `children/1` returns.

  When a child fails to start, the failure is logged and the answer is `:ignore`: the
  supervisor above keeps the feature's entry with no process, where failing would stop
  the app's boot.
  """
  @spec start_feature(Feature.id(), [Supervisor.child_spec() | {module(), term()} | module()]) ::
          {:ok, pid()} | :ignore
  def start_feature(id, children) do
    case Supervisor.start_link(children, strategy: :one_for_one) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error(
          "feature #{inspect(id)} failed to start and is left stopped: " <>
            Exception.format_exit(reason)
        )

        :ignore
    end
  end

  defp not_features(features) do
    for module <- features,
        not feature?(module),
        do: "lists #{inspect(module)}, which does not implement #{inspect(Feature)}"
  end

  @shapes [
    id: "an atom",
    kind: ":core, :personal or :work",
    depends_on: "a list of feature ids",
    config_keys:
      "a list of {key, validator} pairs, each key an atom listed once and each validator a 1-arity function"
  ]

  defp shape_problems(feature) do
    Enum.flat_map(@shapes, fn {callback, expected} ->
      value = apply(feature, callback, [])

      if valid_shape?(callback, value),
        do: [],
        else: [
          "has #{inspect(feature)}.#{callback}/0 return #{inspect(value)}; it must be #{expected}"
        ]
    end)
  end

  defp valid_shape?(:id, id), do: is_atom(id)
  defp valid_shape?(:kind, kind), do: kind in [:core, :personal, :work]
  defp valid_shape?(:depends_on, ids), do: list_of?(ids, &is_atom/1)

  defp valid_shape?(:config_keys, keys),
    do: list_of?(keys, &config_key?/1) and keys == Enum.uniq_by(keys, &elem(&1, 0))

  defp config_key?({key, validator}), do: is_atom(key) and is_function(validator, 1)
  defp config_key?(_entry), do: false

  defp list_of?(value, valid?),
    do: is_list(value) and not List.improper?(value) and Enum.all?(value, valid?)

  # Each `@behaviour` line is stored as its own `behaviour: [module]` attribute.
  defp feature?(module) do
    is_atom(module) and Code.ensure_loaded?(module) and
      Feature in List.flatten(Keyword.get_values(module.module_info(:attributes), :behaviour))
  end

  defp implements?(feature, function, arity) do
    Code.ensure_loaded?(feature) and function_exported?(feature, function, arity)
  end

  defp core_or_listed?(feature, modules), do: feature.kind() == :core or feature.id() in modules

  defp run_validator(_validator, [_, _ | _]), do: {:error, "is set more than once"}
  defp run_validator(validator, []), do: validator.(:error)
  defp run_validator(validator, [value]), do: validator.({:ok, value})

  defp validator_error({_key, _feature, {:ok, _value}}), do: []

  defp validator_error({key, _feature, {:error, reason}}) when is_binary(reason),
    do: [{key, reason}]

  defp validator_error({key, feature, result}) do
    [
      {@registry,
       "has #{inspect(feature)}'s validator for #{inspect(key)} return #{inspect(result)}; " <>
         "it must return {:ok, value} or {:error, reason}, the reason a string"}
    ]
  end

  defp stray_keys(features, enabled, entries) do
    owners =
      for feature <- features, {key, _} <- feature.config_keys(), into: %{}, do: {key, feature}

    for key <- Enum.uniq(Keyword.keys(entries)),
        reason = stray_key(owners[key], enabled),
        do: {key, reason}
  end

  defp stray_key(nil, _enabled), do: "is not a known key"

  defp stray_key(owner, enabled) do
    if owner not in enabled, do: "belongs to #{inspect(owner.id())}, which is not enabled"
  end

  defp module_problem(nil, _kind, _modules, _by_id), do: "is not a known module"

  defp module_problem(feature, kind, modules, by_id) do
    cond do
      feature.kind() == :core ->
        "is a core module and always enabled"

      feature.kind() != kind ->
        "is not allowed on a #{inspect(kind)} install"

      missing = Enum.find(feature.depends_on(), &(not core_or_listed?(by_id[&1], modules))) ->
        "depends on #{inspect(missing)}, which is not enabled"

      true ->
        nil
    end
  end

  defp duplicate_ids(features) do
    for {id, [_, _ | _] = modules} <- Enum.group_by(features, & &1.id()) do
      {last, rest} = List.pop_at(modules, -1)
      "gives id #{inspect(id)} to #{Enum.map_join(rest, ", ", &inspect/1)} and #{inspect(last)}"
    end
  end

  defp dependency_problems(features, by_id) do
    for feature <- features,
        dep_id <- feature.depends_on(),
        problem = dependency_problem(feature, dep_id, by_id[dep_id]),
        do: problem
  end

  defp dependency_problem(feature, dep_id, nil),
    do: "has #{inspect(feature.id())} depend on #{inspect(dep_id)}, which is not a feature"

  defp dependency_problem(feature, dep_id, dep) do
    if dep.kind() not in [:core, feature.kind()] do
      "has #{inspect(feature.kind())} feature #{inspect(feature.id())} depend on " <>
        "#{inspect(dep.kind())} feature #{inspect(dep_id)}; a feature may depend only on " <>
        ":core features and features of its own kind"
    end
  end

  # `:digraph` is Erlang's built-in graph (https://www.erlang.org/doc/apps/stdlib/digraph.html);
  # it lives in ETS tables, so it is deleted once read.
  defp cycle(features) do
    graph = :digraph.new()

    try do
      Enum.each(features, &:digraph.add_vertex(graph, &1.id()))
      # An edge to an unknown id fails quietly; dependency_problems/2 reports it.
      _ =
        for feature <- features, dep_id <- feature.depends_on() do
          :digraph.add_edge(graph, feature.id(), dep_id)
        end

      case Enum.find_value(features, &:digraph.get_short_cycle(graph, &1.id())) do
        nil -> []
        path -> ["has a dependency cycle: " <> Enum.map_join(path, " -> ", &inspect/1)]
      end
    after
      :digraph.delete(graph)
    end
  end

  defp key_clashes(features) do
    claims =
      Enum.map(Config.platform_keys(), &{&1, "platform"}) ++
        for feature <- features,
            {key, _validator} <- feature.config_keys(),
            do: {key, inspect(feature.id())}

    for {key, claimant} <- claims,
        {_key, owner} = List.keyfind(claims, key, 0),
        owner != claimant,
        do: "has #{claimant} claim config key #{inspect(key)}, which #{owner} owns"
  end
end
