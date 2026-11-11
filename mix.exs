defmodule Lanternhall.MixProject do
  use Mix.Project

  def project do
    [
      app: :lanternhall,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        summary: [threshold: 90],
        ignore_modules: [
          # Only compile-time `quote` blocks for `use LanternhallWeb, ...`; runtime
          # coverage can never reach them.
          LanternhallWeb,
          # Test support used only by `mix test --only e2e`, which runs outside this gate.
          LanternhallWeb.E2ECase
        ]
      ],
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        # Mix tasks in lib/mix/tasks call Mix, which is not in the app's runtime deps.
        plt_add_apps: [:mix],
        flags: [:unmatched_returns, :error_handling, :extra_return, :missing_return]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Lanternhall.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp releases do
    [lanternhall: [steps: [&require_digested_assets/1, :assemble]]]
  end

  # With `cache_static_manifest` set (config/prod.exs), the release serves only digested
  # assets; built without them it boots fine but every page loads with no CSS or JS.
  defp require_digested_assets(release) do
    manifest = Application.get_env(:lanternhall, LanternhallWeb.Endpoint)[:cache_static_manifest]

    if manifest && !File.exists?(manifest) do
      Mix.raise("#{manifest} is missing: run `mix assets.deploy` before `mix release`")
    end

    release
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "== 1.8.16"},
      {:phoenix_ecto, "== 4.7.0"},
      {:ecto_sql, "== 3.14.0"},
      {:ecto_sqlite3, "== 0.26.0"},
      {:phoenix_html, "== 4.4.0"},
      {:phoenix_live_reload, "== 1.7.0", only: :dev},
      {:phoenix_live_view, "== 1.2.13"},
      {:lazy_html, "== 0.1.13", only: :test},
      {:phoenix_live_dashboard, "== 0.9.1"},
      {:esbuild, "== 0.10.1", runtime: Mix.env() == :dev},
      {:tailwind, "== 0.5.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "== 1.2.0"},
      {:telemetry_poller, "== 1.3.0"},
      {:jason, "== 1.4.5"},
      {:tz, "== 0.28.4"},
      {:bandit, "== 1.14.1"},
      {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
      {:sobelow, "== 0.18.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "== 1.4.8", only: [:dev, :test], runtime: false},
      {:phoenix_test, "== 0.14.0", only: :test, runtime: false},
      {:phoenix_test_playwright, "== 0.19.0", only: :test, runtime: false},
      # Pinned directly: phoenix_test_playwright's `~> 0.15` would allow a newer one.
      {:playwright_ex, "== 0.15.0", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind lanternhall", "esbuild lanternhall"],
      "assets.deploy": [
        "compile",
        "tailwind lanternhall --minify",
        "esbuild lanternhall --minify",
        "phx.digest"
      ],
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "sobelow --config",
        "cmd pnpm --dir assets exec biome check js scripts",
        "test --exclude e2e --cover"
      ]
    ]
  end
end
