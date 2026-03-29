defmodule CadenceSimulator.MixProject do
  use Mix.Project

  def project do
    [
      app: :cadence_simulator,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: CadenceSimulator.CLI],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CadenceSimulator.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:cadence, in_umbrella: true, runtime: false},
      {:req, "~> 0.5"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
