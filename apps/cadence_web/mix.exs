defmodule CadenceWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_web,
      workspace: workspace(),
      version: "0.1.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      # The dev code reloader compiles the :cadence path dep on every request, and
      # Mix wipes our consolidation dir whenever it compiles a dep, forcing a full
      # re-consolidation per request. Skip consolidation in dev to break that loop.
      consolidate_protocols: Mix.env() != :dev,
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
        "test.browser.full": :test,
        "test.browser.federation": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp workspace do
    [
      tags: [{:layer, :application}],
      affected_by: ["../../mix.exs", "../../.workspace.exs"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:live_vue, "== 1.2.2"},
      {:bandit, "~> 1.5"},
      {:cadence, path: "../cadence", env: Mix.env()},
      {:cadence_catalog, path: "../../packages/cadence_catalog", env: Mix.env()},
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
      {:live_toast, "~> 0.9.0"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:phoenix, "~> 1.8.12"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_vite, "~> 0.5"},
      {:swoosh, "~> 1.17"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:tidewave, "~> 0.5", only: [:dev]}
    ]
  end

  defp aliases do
    [
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "phoenix_vite.npm assets install"
      ],
      "assets.build": ["tailwind cadence_web", "phoenix_vite.npm vite build"],
      "assets.deploy": [
        "tailwind cadence_web --minify",
        "phoenix_vite.npm vite build",
        "cmd --cd ../../frontend corepack pnpm@11.22.0 run build:publication",
        "phx.digest"
      ],
      "test.browser": [
        "test.browser.federation"
      ],
      "test.browser.full": [
        "test.browser.federation"
      ],
      "test.browser.federation": [
        "cmd --cd ../../frontend corepack pnpm@11.22.0 run test:browser:contract",
        "cmd node ../../frontend/tools/phoenix/run_federation_publication_build.mjs assets.deploy",
        "cmd env CADENCE_BROWSER_PROPS_DIFF=true MIX_ENV=test mix test --include browser_smoke --only browser_smoke browser_test/cadence_web/assets/federation_browser_smoke_test.exs browser_test/cadence_web/assets/admin_mode_browser_smoke_test.exs browser_test/cadence_web/assets/command_workspace_browser_test.exs browser_test/cadence_web/assets/spacecraft_configuration_browser_test.exs browser_test/cadence_web/assets/settings_browser_test.exs test/cadence_web/ops_contact_scheduling_page_test.exs"
      ]
    ]
  end
end
