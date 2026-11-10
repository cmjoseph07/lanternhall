defmodule Mix.Tasks.Lanternhall.Config.Check do
  @shortdoc "Validates an install config file without starting the app"

  @moduledoc """
  Validates an install config file without starting the app, with the same checks and
  messages as boot (`Lanternhall.Platform.Config.check/3`), against the feature registry
  in `config/config.exs`.

      mix lanternhall.config.check ~/.config/lanternhall/config.exs

  Prints one line per problem and exits with status 1, or confirms the file is valid.
  """
  use Mix.Task

  alias Lanternhall.Platform.{Config, Features}

  # Compile only: `app.config` would evaluate config/runtime.exs, which loads the
  # install config this task is meant to check. Mix has already loaded config/config.exs,
  # so the feature registry is set.
  @requirements ["compile"]

  @impl Mix.Task
  def run([path]) do
    path = Path.expand(path)

    case Config.check(path, System.get_env(), Features.all()) do
      {:ok, config} ->
        Mix.shell().info("lanternhall config: #{path} is valid (#{inspect(config.kind)} install)")

      {:error, errors} ->
        Mix.shell().error(Config.format_errors(errors))
        exit({:shutdown, 1})
    end
  end

  def run(_args), do: Mix.raise("usage: mix lanternhall.config.check <path>")
end
