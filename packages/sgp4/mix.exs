defmodule Sgp4.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :sgp4,
      name: "SGP4",
      workspace: workspace(),
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Dependency-free near-earth SGP4 (Vallado 2006, WGS72) and pass search",
      deps: []
    ]
  end

  def application, do: [extra_applications: []]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp workspace do
    [
      tags: [{:layer, :foundation}],
      affected_by: ["../../mix.exs", "../../.workspace.exs"]
    ]
  end
end
