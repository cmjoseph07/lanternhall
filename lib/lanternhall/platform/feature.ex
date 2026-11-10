defmodule Lanternhall.Platform.Feature do
  @moduledoc """
  The contract every Lanternhall feature implements once, in `lib/lanternhall/<feature>/feature.ex`
  (SPEC-platform.md section 3.2). A feature is one module from SPEC.md section 3; the
  word "module" already means an Elixir `defmodule`.

  Platform reads these callbacks through `Lanternhall.Platform.Features`; it never names a
  feature module directly. The list of implementations lives only in `config/config.exs`.
  """

  alias Lanternhall.Platform.Config

  @type id :: atom()
  @type kind :: :core | :personal | :work

  @typedoc """
  Checks one install config key. It receives `Keyword.fetch/2`'s result for the key, so
  `:error` means the key is absent: return `{:ok, default}` for an optional key, or
  `{:error, reason}` for a required one. The reason reads after the key name, as in
  `"must be a positive integer, got 0"`.
  """
  @type validator :: ({:ok, term()} | :error -> {:ok, term()} | {:error, String.t()})

  @doc "Module id from SPEC.md section 3, as a snake_case atom (`:needs_you`)."
  @callback id() :: id()

  @doc "`:core` features are always enabled; the others only on installs of their kind."
  @callback kind() :: kind()

  @doc "Feature ids this feature may call; each must be `:core` or of the same kind."
  @callback depends_on() :: [id()]

  @doc "Keys this feature adds to the install config, each with its validator."
  @callback config_keys() :: [{atom(), validator()}]

  @doc """
  Child specs to supervise while the feature is enabled, given the validated config.
  They run under the feature's own supervisor, so child ids need only be unique within
  the feature.
  """
  @callback children(Config.t()) :: [Supervisor.child_spec() | {module(), term()} | module()]

  @optional_callbacks children: 1
end
