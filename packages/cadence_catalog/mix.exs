defmodule CadenceCatalog.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_catalog,
      workspace: workspace(),
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger, :xmerl]
    ]
  end

  defp workspace do
    [
      tags: [{:layer, :foundation}],
      affected_by: ["../../mix.exs", "../../.workspace.exs"]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
