defmodule CadenceSimulator.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_simulator,
      workspace: workspace(),
      version: "0.1.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: CadenceSimulator.CLI, app: nil],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {CadenceSimulator.Application, []}
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

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:cadence_catalog, path: "../../packages/cadence_catalog", env: Mix.env()},
      {:cadence_ccsds, path: "../../packages/cadence_ccsds", env: Mix.env()},
      {:cadence, path: "../cadence", env: Mix.env(), only: :test},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.18"},
      {:req, "~> 0.5"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
