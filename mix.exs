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
        precommit: :test,
        "test.fast": :test,
        "test.runtime": :test,
        "test.management": :test,
        "test.control": :test,
        "test.data": :test,
        "test.projections": :test,
        "test.planes": :test,
        "test.integration": :test,
        "test.browser": :test,
        "test.browser.full": :test
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
      "test.fast": [&run_fast_tests/1],
      "test.runtime": [&run_runtime_tests/1],
      "test.management": [&run_plane_tests(:management, &1)],
      "test.control": [&run_plane_tests(:control, &1)],
      "test.data": [&run_plane_tests(:data, &1)],
      "test.projections": [&run_plane_tests(:projections, &1)],
      "test.planes": [&run_all_plane_tests/1],
      "test.integration": [&run_integration_tests/1],
      "test.browser": [&run_browser_tests/1],
      "test.browser.full": [&run_full_browser_tests/1],
      precommit: [
        "format",
        "compile --warnings-as-errors",
        "credo --strict",
        "cadence.extensions.check",
        "cadence.architecture.check --summary",
        "test.planes",
        "test"
      ]
    ]
  end

  defp run_fast_tests(args) do
    run_child_tests([
      "--exclude",
      "runtime",
      "--exclude",
      "config",
      "--exclude",
      "integration"
      | args
    ])
  end

  defp run_runtime_tests(args) do
    run_child_mix_command(:cadence, ["db.setup.test"])
    run_child_test_command(:cadence, cadence_test_args(["--only", "runtime" | args]))
  end

  defp run_all_plane_tests(args) do
    Enum.each([:management, :control, :data, :projections], &run_plane_tests(&1, args))
  end

  defp run_plane_tests(plane, args) do
    if plane == :management do
      run_child_mix_command(:cadence, ["db.setup.test"])
    end

    run_child_test_command(
      :cadence,
      ["--no-start" | plane_test_paths(plane)] ++ args,
      [{"CADENCE_TEST_PLANE", Atom.to_string(plane)}]
    )
  end

  defp run_integration_tests(args) do
    run_child_mix_command(:cadence, ["db.setup.test"])

    run_child_test_command(:cadence, cadence_test_args(["--only", "integration" | args]))
    run_child_test_command(:cadence_simulator, ["--only", "integration" | args])
    run_child_test_command(:cadence_web, ["--only", "integration" | args])
  end

  defp run_child_tests(args) do
    args_by_app = child_test_args(args)

    if args = Map.get(args_by_app, :cadence) do
      run_child_mix_command(:cadence, ["db.setup.test"])
      run_child_test_command(:cadence, cadence_test_args(args))
    end

    if args = Map.get(args_by_app, :cadence_catalog) do
      run_child_test_command(:cadence_catalog, args)
    end

    if args = Map.get(args_by_app, :cadence_ccsds) do
      run_child_test_command(:cadence_ccsds, args)
    end

    if args = Map.get(args_by_app, :cadence_simulator) do
      run_child_test_command(:cadence_simulator, args)
    end

    if args = Map.get(args_by_app, :cadence_web) do
      run_child_test_command(:cadence_web, args)
    end
  end

  defp run_browser_tests(args) do
    run_child_test_command(:cadence_web, [
      "--include",
      "browser_smoke",
      "--only",
      "browser_smoke",
      "browser_test/cadence_web/assets/dashboard_rendered_viewport_smoke_test.exs"
      | args
    ])
  end

  defp run_full_browser_tests(args) do
    run_child_test_command(:cadence_web, [
      "--include",
      "browser",
      "--include",
      "browser_smoke",
      "browser_test/cadence_web/assets"
      | args
    ])
  end

  defp child_test_args(args) do
    selected_apps =
      args
      |> Enum.flat_map(&child_apps_for_arg/1)
      |> Enum.uniq()

    case selected_apps do
      [] ->
        %{
          cadence: args,
          cadence_catalog: args,
          cadence_ccsds: args,
          cadence_simulator: args,
          cadence_web: args
        }

      apps ->
        Map.new(apps, &{&1, rewrite_child_args(args, &1)})
    end
  end

  defp child_apps_for_arg(arg) do
    [:cadence, :cadence_catalog, :cadence_ccsds, :cadence_simulator, :cadence_web]
    |> Enum.filter(&child_path_arg?(arg, &1))
  end

  defp rewrite_child_args(args, app) do
    Enum.flat_map(args, fn arg ->
      cond do
        child_path_arg?(arg, app) -> [child_relative_arg(arg, app)]
        known_child_path_arg?(arg) -> []
        true -> [arg]
      end
    end)
  end

  defp child_path_arg?(arg, app) when is_binary(arg) and is_atom(app) do
    path = child_path(app)
    arg == path or String.starts_with?(arg, path <> "/")
  end

  defp known_child_path_arg?(arg) when is_binary(arg) do
    Enum.any?(
      [:cadence, :cadence_catalog, :cadence_ccsds, :cadence_simulator, :cadence_web],
      &child_path_arg?(arg, &1)
    )
  end

  defp child_relative_arg(arg, app) do
    path = child_path(app)

    if arg == path, do: ".", else: String.replace_prefix(arg, path <> "/", "")
  end

  defp child_path(:cadence), do: "apps/cadence"
  defp child_path(:cadence_catalog), do: "apps/cadence_catalog"
  defp child_path(:cadence_ccsds), do: "apps/cadence_ccsds"
  defp child_path(:cadence_simulator), do: "apps/cadence_simulator"
  defp child_path(:cadence_web), do: "apps/cadence_web"

  defp plane_test_paths(:data) do
    [
      "plane_test/data",
      "test/cadence/runtime/ingress_persistence_projector_test.exs",
      "test/cadence/runtime/processed_ingress_batch_test.exs",
      "test/cadence/runtime/provider_ingress_executor_test.exs",
      "test/cadence/runtime/timer_service_test.exs",
      "test/cadence/runtime/transport_runtime_test.exs"
    ]
  end

  defp plane_test_paths(plane), do: ["plane_test/#{plane}"]

  defp cadence_test_args(args) do
    # The cadence child app owns globally named runtimes and a shared DB sandbox.
    # Keep the umbrella gate deterministic unless a caller explicitly overrides it.
    if Enum.any?(args, &String.starts_with?(&1, "--max-cases")) do
      args
    else
      ["--max-cases", "1" | args]
    end
  end

  defp run_child_mix_command(app, args, extra_env \\ [])
       when is_atom(app) and is_list(args) and is_list(extra_env) do
    {_output, status} =
      System.cmd("mix", args,
        cd: child_path(app),
        env: [{"MIX_ENV", Atom.to_string(Mix.env())} | extra_env],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0 do
      Mix.raise("#{app} mix command failed: mix #{Enum.join(args, " ")}")
    end
  end

  defp run_child_test_command(app, args, extra_env \\ []) when is_atom(app) do
    run_child_mix_command(app, ["test" | args], extra_env)
  end
end
