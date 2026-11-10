defmodule Lanternhall.Platform.Features do
  @moduledoc """
  The feature registry (SPEC-platform.md section 3.2): the `Lanternhall.Platform.Feature`
  implementations listed in `config :lanternhall, :features`, checked for consistency,
  and resolved against an install's kind and modules into the enabled set.

  The enabled set is every `:core` feature plus those the install config lists. It is
  stored in `Lanternhall.Platform.Config` at boot, and everything a feature contributes is
  read from that set only, so a disabled feature contributes nothing.

  Problems are data, like the config's own: `{:features, reason}` for a broken registry
  (a code problem) and `{:modules, reason}` for an install that enables the wrong modules.
  """

  alias Lanternhall.Platform.{Config, Feature}

  @doc "Every feature implementation, in the order `config/config.exs` lists them."
  @spec all() :: [module()]
  def all, do: Application.fetch_env!(:lanternhall, :features)

  @doc """
  Checks the registry itself: each entry implements the behaviour, ids are unique,
  dependencies exist, are `:core` or of the dependent's kind and form no cycle, and no two
  owners claim the same install config key.
  """
  @spec validate([module()]) :: :ok | {:error, [Config.error()]}
  def validate(features) do
    problems =
      case Enum.reject(features, &feature?/1) do
        [] ->
          by_id = Map.new(features, &{&1.id(), &1})

          duplicate_ids(features) ++
            dependency_problems(features, by_id) ++ cycle(features) ++ key_clashes(features)

        not_features ->
          for module <- not_features,
              do: "lists #{inspect(module)}, which does not implement #{inspect(Feature)}"
      end

    case problems do
      [] -> :ok
      problems -> {:error, Enum.map(problems, &{:features, &1})}
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
      [] -> {:ok, Enum.filter(features, &enabled?(&1, modules))}
      errors -> {:error, errors}
    end
  end

  @doc "Child specs of every enabled feature, in registry order."
  @spec children(Config.t()) :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children(%Config{features: features} = config) do
    for feature <- features,
        implements?(feature, :children, 1),
        child <- feature.children(config),
        do: child
  end

  # Each `@behaviour` line is stored as its own `behaviour: [module]` attribute.
  defp feature?(module) do
    is_atom(module) and Code.ensure_loaded?(module) and
      Feature in List.flatten(Keyword.get_values(module.module_info(:attributes), :behaviour))
  end

  defp implements?(feature, function, arity) do
    Code.ensure_loaded?(feature) and function_exported?(feature, function, arity)
  end

  defp enabled?(feature, modules), do: feature.kind() == :core or feature.id() in modules

  defp module_problem(nil, _kind, _modules, _by_id), do: "is not a known module"

  defp module_problem(feature, kind, modules, by_id) do
    cond do
      feature.kind() == :core ->
        "is a core module and always enabled"

      feature.kind() != kind ->
        "is not allowed on a #{inspect(kind)} install"

      missing = Enum.find(feature.depends_on(), &(not enabled?(by_id[&1], modules))) ->
        "depends on #{inspect(missing)}, which is not enabled"

      true ->
        nil
    end
  end

  defp duplicate_ids(features) do
    for {id, [first, second | _]} <- Enum.group_by(features, & &1.id()) do
      "gives id #{inspect(id)} to both #{inspect(first)} and #{inspect(second)}"
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

  # Reports the first cycle found, walking features in registry order. `:digraph` is
  # Erlang's built-in graph (https://www.erlang.org/doc/apps/stdlib/digraph.html); it
  # lives in ETS tables, so it is deleted once read.
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

  # Each key has one owner: platform, or the first feature that claims it.
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
