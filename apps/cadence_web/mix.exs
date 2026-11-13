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
        &run_browser_contract_tests/1,
        &build_federation_assets/1,
        &run_federation_browser_tests/1
      ]
    ]
  end

  # The federation browser tests. With CADENCE_BROWSER_SHARD=k/n (CI's parallel browser jobs)
  # only every n-th file from the k-th runs, so the order balances the shards: the two
  # federation-fixture suites, which build every plugin, are the heaviest and alternate.
  @federation_browser_tests [
    "browser_test/cadence_web/assets/federation_browser_smoke_test.exs",
    "test/cadence_web/ops_contact_scheduling_page_test.exs",
    "browser_test/cadence_web/assets/command_workspace_browser_test.exs",
    "browser_test/cadence_web/assets/admin_mode_browser_smoke_test.exs",
    "browser_test/cadence_web/assets/spacecraft_configuration_browser_test.exs",
    "browser_test/cadence_web/assets/settings_browser_test.exs"
  ]

  # The node contract tests for the browser harness run once: unsharded, or in shard 1.
  defp run_browser_contract_tests(_args) do
    case browser_shard() do
      {k, _n} when k > 1 ->
        Mix.shell().info("Browser contract tests run in shard 1")

      _unsharded_or_first ->
        Mix.Task.reenable("cmd")

        Mix.Task.run("cmd", [
          "--cd",
          "../../frontend",
          "corepack",
          "pnpm@11.22.0",
          "run",
          "test:browser:contract"
        ])
    end
  end

  defp run_federation_browser_tests(_args) do
    files =
      case browser_shard() do
        nil -> @federation_browser_tests
        {k, n} -> shard_files(@federation_browser_tests, k, n)
      end

    Mix.Task.reenable("cmd")

    Mix.Task.run(
      "cmd",
      ~w(env CADENCE_BROWSER_PROPS_DIFF=true MIX_ENV=test mix test --include browser_smoke
         --only browser_smoke --slowest-modules 10) ++ files
    )
  end

  defp shard_files(files, k, n) do
    case for({file, index} <- Enum.with_index(files), rem(index, n) == k - 1, do: file) do
      # mix test without files would run every browser_smoke test instead of none.
      [] -> Mix.raise("CADENCE_BROWSER_SHARD=#{k}/#{n} selects no browser test files")
      selected -> selected
    end
  end

  defp browser_shard do
    case System.get_env("CADENCE_BROWSER_SHARD") do
      nil ->
        nil

      shard ->
        with [k, n] <- String.split(shard, "/"),
             {k, ""} <- Integer.parse(k),
             {n, ""} <- Integer.parse(n),
             true <- k in 1..n//1 do
          {k, n}
        else
          _invalid ->
            Mix.raise("CADENCE_BROWSER_SHARD must be k/n with 1 <= k <= n, got #{shard}")
        end
    end
  end

  # CI builds these assets once (its browser-assets job) and hands them to the browser jobs,
  # which set CADENCE_BROWSER_ASSETS_PREBUILT=1. Everywhere else the alias builds them itself.
  defp build_federation_assets(_args) do
    if System.get_env("CADENCE_BROWSER_ASSETS_PREBUILT") == "1" do
      unless File.regular?("priv/static/cache_manifest.json") do
        Mix.raise(
          "CADENCE_BROWSER_ASSETS_PREBUILT=1 but priv/static has no digested assets " <>
            "(cache_manifest.json); build them with mix assets.deploy"
        )
      end

      Mix.shell().info("Using prebuilt browser assets (CADENCE_BROWSER_ASSETS_PREBUILT=1)")
    else
      Mix.Task.reenable("cmd")

      Mix.Task.run("cmd", [
        "node",
        "../../frontend/tools/phoenix/run_federation_publication_build.mjs",
        "assets.deploy"
      ])
    end
  end
end
