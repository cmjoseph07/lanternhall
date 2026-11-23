defmodule Lanternhall.Application do
  @moduledoc false

  use Application

  alias Lanternhall.Platform.{Config, Features, Uptime}

  @impl true
  def start(_type, _args) do
    Uptime.mark_started()

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
          LanternhallWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: Lanternhall.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
