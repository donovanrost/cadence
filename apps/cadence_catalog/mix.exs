defmodule CadenceCatalog.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_catalog,
      workspace: workspace(),
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  defp workspace do
    [
      tags: [{:layer, :foundation}],
      affected_by: ["../../mix.exs", "../../mix.lock", "../../config"]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
