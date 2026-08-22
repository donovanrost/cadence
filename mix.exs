defmodule CadenceWorkspace.MixProject do
  use Mix.Project

  @child_apps [:cadence, :cadence_catalog, :ccsds, :cadence_simulator, :cadence_web]

  def project do
    [
      app: :cadence_workspace,
      workspace: [type: :workspace],
      elixirc_paths: [],
      version: "0.1.0",
      elixir: "~> 1.15",
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        "precommit.checks": :test,
        "precommit.affected": :test,
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
      {:cadence_simulator, path: "apps/cadence_simulator", env: Mix.env(), runtime: false},
      {:cadence_web, path: "apps/cadence_web", env: Mix.env(), runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:workspace, "~> 0.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", workspace_command("deps.get")],
      "format.all": [&run_format_all/1],
      test: [workspace_test_command()],
      "test.fast": [
        workspace_test_command(
          task_args: ["--exclude", "runtime", "--exclude", "config", "--exclude", "integration"]
        )
      ],
      "test.runtime": [
        workspace_test_command(projects: [:cadence], task_args: ["--only", "runtime"])
      ],
      "test.management": [plane_test_command(:management)],
      "test.control": [plane_test_command(:control)],
      "test.data": [plane_test_command(:data)],
      "test.projections": [plane_test_command(:projections)],
      "test.planes": [&run_plane_tests/1],
      "test.integration": [
        workspace_test_command(
          projects: [:cadence, :cadence_simulator, :cadence_web],
          task_args: ["--only", "integration"]
        )
      ],
      "test.browser": [
        workspace_command("test.browser",
          projects: [:cadence_web],
          env: [{"MIX_ENV", "test"}]
        )
      ],
      "test.browser.full": [
        workspace_command("test.browser.full",
          projects: [:cadence_web],
          env: [{"MIX_ENV", "test"}]
        )
      ],
      "precommit.checks": [
        "format.all",
        workspace_command("compile",
          env: [{"MIX_ENV", "test"}],
          task_args: ["--warnings-as-errors"]
        ),
        "credo --strict",
        "workspace.check",
        workspace_command("cadence.extensions.check",
          projects: [:cadence],
          env: [{"MIX_ENV", "test"}]
        ),
        workspace_command("cadence.architecture.check",
          projects: [:cadence],
          env: [{"MIX_ENV", "test"}],
          task_args: ["--summary"]
        )
      ],
      precommit: [
        "precommit.checks",
        "test.planes",
        "test"
      ],
      "precommit.affected": [
        "precommit.checks",
        affected_plane_test_command(:management),
        affected_plane_test_command(:control),
        affected_plane_test_command(:data),
        affected_plane_test_command(:projections),
        workspace_test_command(affected: true)
      ]
    ]
  end

  defp workspace_test_command(opts \\ []) do
    workspace_command("test", with_test_env(opts))
  end

  defp plane_test_command(plane, opts \\ []) do
    workspace_test_command(plane_test_options(plane, opts))
  end

  defp affected_plane_test_command(plane) do
    plane_test_command(plane, affected: true)
  end

  defp run_plane_tests(args) do
    Enum.each([:management, :control, :data, :projections], fn plane ->
      Mix.Task.reenable("workspace.run")

      Mix.Task.run(
        "workspace.run",
        workspace_command_args(
          "test",
          plane |> plane_test_options(task_args: args) |> with_test_env()
        )
      )
    end)
  end

  defp plane_test_options(plane, opts) do
    task_args = ["--no-start" | plane_test_paths(plane)] ++ Keyword.get(opts, :task_args, [])
    env = [{"CADENCE_TEST_PLANE", Atom.to_string(plane)} | Keyword.get(opts, :env, [])]

    opts
    |> Keyword.put(:projects, [:cadence])
    |> Keyword.put(:env, env)
    |> Keyword.put(:task_args, task_args)
  end

  defp with_test_env(opts) do
    Keyword.update(opts, :env, [{"MIX_ENV", "test"}], &[{"MIX_ENV", "test"} | &1])
  end

  defp workspace_command(task, opts \\ []) do
    ["workspace.run" | workspace_command_args(task, opts)]
    |> Enum.join(" ")
  end

  defp workspace_command_args(task, opts) do
    project_args =
      opts
      |> Keyword.get(:projects, [])
      |> Enum.flat_map(&["-p", Atom.to_string(&1)])

    affected_args = if Keyword.get(opts, :affected, false), do: ["--affected"], else: []

    env_args =
      opts
      |> Keyword.get(:env, [])
      |> Enum.flat_map(fn {name, value} -> ["--env-var", "#{name}=#{value}"] end)

    task_args = Keyword.get(opts, :task_args, [])

    ["-t", task, "--order", "postorder", "--early-stop"]
    |> Kernel.++(project_args)
    |> Kernel.++(affected_args)
    |> Kernel.++(env_args)
    |> Kernel.++(["--" | task_args])
  end

  defp run_format_all(args) do
    option_args = Enum.filter(args, &String.starts_with?(&1, "-"))
    path_args = args -- option_args

    if path_args == [] do
      Mix.Task.run("format", option_args)
      Enum.each(@child_apps, &run_child_mix_command(&1, ["format" | option_args]))
    else
      root_paths = Enum.reject(path_args, &known_child_path_arg?/1)

      if root_paths != [] do
        Mix.Task.run("format", option_args ++ root_paths)
      end

      Enum.each(@child_apps, &run_child_format(&1, path_args, option_args))
    end
  end

  defp run_child_format(app, path_args, option_args) do
    child_paths =
      path_args
      |> Enum.filter(&child_path_arg?(&1, app))
      |> Enum.map(&child_relative_arg(&1, app))

    if child_paths != [] do
      run_child_mix_command(app, ["format" | option_args ++ child_paths])
    end
  end

  defp child_path_arg?(arg, app) when is_binary(arg) and is_atom(app) do
    path = child_path(app)
    arg == path or String.starts_with?(arg, path <> "/")
  end

  defp known_child_path_arg?(arg) when is_binary(arg) do
    Enum.any?(@child_apps, &child_path_arg?(arg, &1))
  end

  defp child_relative_arg(arg, app) do
    path = child_path(app)

    if arg == path, do: ".", else: String.replace_prefix(arg, path <> "/", "")
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

  defp child_path(:cadence), do: "apps/cadence"
  defp child_path(:cadence_catalog), do: "packages/cadence_catalog"
  defp child_path(:ccsds), do: "packages/ccsds"
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
end
