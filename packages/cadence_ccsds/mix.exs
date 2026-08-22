defmodule CadenceCCSDS.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_ccsds,
      workspace: workspace(),
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp workspace do
    [
      tags: [{:layer, :foundation}],
      affected_by: ["../../mix.exs", "../../.workspace.exs"]
    ]
  end
end
