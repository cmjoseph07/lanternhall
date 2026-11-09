defmodule Lanternhall.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LanternhallWeb.Telemetry,
      Lanternhall.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:lanternhall, :ecto_repos), skip: skip_migrations?()},
      {Phoenix.PubSub, name: Lanternhall.PubSub},
      # Start a worker by calling: Lanternhall.Worker.start_link(arg)
      # {Lanternhall.Worker, arg},
      # Start to serve requests, typically the last entry
      LanternhallWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lanternhall.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
