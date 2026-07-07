defmodule CadenceWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CadenceWeb.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.browser": :test,
        "test.browser.full": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:cadence, in_umbrella: true},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.1"},
      {:swoosh, "~> 1.17"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:tidewave, "~> 0.5", only: [:dev]}
    ]
  end

  defp aliases do
    [
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind cadence_web", "esbuild cadence_web"],
      "assets.deploy": [
        "tailwind cadence_web --minify",
        "esbuild cadence_web --minify",
        "phx.digest"
      ],
      "test.browser": [
        "test --include browser_smoke --only browser_smoke test/cadence_web/assets/dashboard_rendered_viewport_smoke_test.exs"
      ],
      "test.browser.full": [
        "test --include browser --include browser_smoke test/cadence_web/assets/dashboard_rendered_viewport_smoke_test.exs"
      ]
    ]
  end
end
