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
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CadenceWeb.Application, []}
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
      {:bandit, "~> 1.5"},
      {:cadence, path: "../cadence", env: Mix.env()},
      {:cadence_catalog, path: "../../packages/cadence_catalog", env: Mix.env()},
      {:jason, "~> 1.4"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:phoenix, "~> 1.8.12"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2"},
      {:swoosh, "~> 1.17"},
      {:tidewave, "~> 0.5", only: [:dev]}
    ]
  end
end
