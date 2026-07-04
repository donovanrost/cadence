defmodule CadenceUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
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
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: [&run_child_tests/1],
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp run_child_tests(args) do
    run_in_child(:cadence, fn ->
      Mix.Task.run("db.setup.test")
      Mix.Task.reenable("test")
      Mix.Task.run("test", cadence_test_args(args))
    end)

    run_in_child(:cadence_simulator, fn ->
      Mix.Task.reenable("test")
      Mix.Task.run("test", args)
    end)

    run_child_test_command(:cadence_web, args)
  end

  defp cadence_test_args(args) do
    # The cadence child app owns globally named runtimes and a shared DB sandbox.
    # Keep the umbrella gate deterministic unless a caller explicitly overrides it.
    if Enum.any?(args, &String.starts_with?(&1, "--max-cases")) do
      args
    else
      ["--max-cases", "1" | args]
    end
  end

  defp run_in_child(app, fun) when is_atom(app) and is_function(fun, 0) do
    path = Path.join("apps", Atom.to_string(app))

    Mix.Project.in_project(app, path, fn _module ->
      fun.()
    end)
  end

  defp run_child_test_command(app, args) when is_atom(app) do
    path = Path.join("apps", Atom.to_string(app))

    {_output, status} =
      System.cmd("mix", ["test" | args],
        cd: path,
        env: [{"MIX_ENV", Atom.to_string(Mix.env())}],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.raise("#{app} tests failed")
    end
  end
end
