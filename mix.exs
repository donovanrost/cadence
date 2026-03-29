defmodule CadenceUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test
      ]
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: [&run_child_tests/1],
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "test"
      ]
    ]
  end

  defp run_child_tests(args) do
    run_in_child(:cadence, fn ->
      Mix.Task.run("db.setup.test")
      Mix.Task.reenable("test")
      Mix.Task.run("test", args)
    end)

    run_in_child(:cadence_simulator, fn ->
      Mix.Task.reenable("test")
      Mix.Task.run("test", args)
    end)

    run_in_child(:cadence_web, fn ->
      Mix.Task.reenable("test")
      Mix.Task.run("test", args)
    end)
  end

  defp run_in_child(app, fun) when is_atom(app) and is_function(fun, 0) do
    path = Path.join("apps", Atom.to_string(app))

    Mix.Project.in_project(app, path, fn _module ->
      fun.()
    end)
  end
end
