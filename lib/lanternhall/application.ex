defmodule Lanternhall.Application do
  @moduledoc false

  use Application

  alias Lanternhall.Platform.{Config, Features}

  @impl true
  def start(_type, _args) do
    # Validated by config/runtime.exs before any app started.
    config = Config.take_from_app_env()

    children =
      [
        LanternhallWeb.Telemetry,
        Lanternhall.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:lanternhall, :ecto_repos), skip: skip_migrations?()},
        {Phoenix.PubSub, name: Lanternhall.PubSub}
      ] ++
        Features.children(config) ++
        [
          # Last, so requests are served only once everything they need is running.
          LanternhallWeb.Endpoint
        ]

    # Each child restarts on its own; the others keep running.
    opts = [strategy: :one_for_one, name: Lanternhall.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Migrations run at boot in a release only; in dev and test, Mix tasks run them.
  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
