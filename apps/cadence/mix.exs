defmodule Cadence.MixProject do
  use Mix.Project

  alias Mix.Tasks.Test, as: TestTask

  def project do
    [
      app: :cadence,
      workspace: workspace(),
      version: "0.1.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Cadence.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp workspace do
    [
      tags: [{:layer, :domain}],
      affected_by: ["../../mix.exs", "../../.workspace.exs"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cadence_catalog, path: "../../packages/cadence_catalog", env: Mix.env()},
      {:cadence_ccsds, path: "../../packages/cadence_ccsds", env: Mix.env()},
      {:ecto_sql, "~> 3.13"},
      {:jason, "~> 1.4"},
      {:nimble_parsec, "~> 1.4"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:phoenix_pubsub, "~> 2.1"},
      {:postgrex, ">= 0.0.0"},
      {:req, "~> 0.5"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end

  defp aliases do
    [
      "db.setup.test": ["ecto.create --quiet", "ecto.migrate --quiet"],
      test: [&run_tests/1]
    ]
  end

  defp run_tests(args) do
    Mix.Task.run("db.setup.test")
    TestTask.run(args)
  end
end
