defmodule Mix.Tasks.Cadence.Architecture.Check do
  @moduledoc """
  Reports source-size pressure and enforces ratcheted dependency boundaries.

  ## Usage

      mix cadence.architecture.check

  ## Options

    * `--production-file-limit` - production `.ex` line limit, defaults to 1000
    * `--test-file-limit` - test source line limit, defaults to 1500
    * `--test-function-limit` - individual `test` block line limit, defaults to 300
    * `--xref-json` - verify a prepared JSON graph against current domain and web compiler references
    * `--skip-dependencies` - run only the advisory source-size diagnostic
    * `--summary` - print counts without listing every finding
    * `--strict` - fail when any source-size finding is present
  """

  use Mix.Task

  alias Cadence.Architecture.{CompiledGraph, DependencyBoundary, SourceSize}

  @shortdoc "Check architecture size and dependency boundaries"

  @switches [
    production_file_limit: :integer,
    test_file_limit: :integer,
    test_function_limit: :integer,
    xref_json: :string,
    skip_dependencies: :boolean,
    summary: :boolean,
    strict: :boolean
  ]

  @impl true
  def run(args) do
    Mix.Task.run("compile")

    {opts, remaining, invalid} = OptionParser.parse(args, strict: @switches)
    validate_args!(remaining, invalid)
    validate_limits!(opts)

    repo_root = SourceSize.repo_root!()
    findings = SourceSize.scan(repo_root, opts)

    unless opts[:summary] do
      Enum.each(findings, fn finding ->
        Mix.shell().info("warning: " <> SourceSize.format_finding(finding))
      end)
    end

    Mix.shell().info(summary(findings))
    dependency_result = maybe_check_dependencies(repo_root, opts)

    if Keyword.get(opts, :strict, false) and findings != [] do
      Mix.raise("Architecture source-size check found #{length(findings)} violation(s).")
    end

    maybe_raise_dependency_failure!(dependency_result)
  end

  defp validate_args!([], []), do: :ok

  defp validate_args!(_remaining, invalid) when invalid != [] do
    Mix.raise("Invalid options: #{inspect(invalid)}")
  end

  defp validate_args!(remaining, _invalid) do
    Mix.raise("Unexpected arguments: #{inspect(remaining)}")
  end

  defp validate_limits!(opts) do
    for {key, value} <- opts,
        key in [:production_file_limit, :test_file_limit, :test_function_limit],
        value <= 0 do
      Mix.raise("#{String.replace(to_string(key), "_", "-")} must be a positive integer")
    end
  end

  defp summary(findings) do
    counts = Enum.frequencies_by(findings, & &1.kind)

    "Architecture source-size pressure: " <>
      "#{Map.get(counts, :production_file, 0)} production files, " <>
      "#{Map.get(counts, :test_file, 0)} test files, " <>
      "#{Map.get(counts, :test_function, 0)} test functions."
  end

  defp maybe_check_dependencies(repo_root, opts) do
    case Keyword.get(opts, :skip_dependencies, false) do
      true -> :skipped
      false -> check_dependencies(repo_root, opts)
    end
  end

  defp check_dependencies(repo_root, opts) do
    graph = load_xref_graph!(repo_root, opts)
    findings = DependencyBoundary.findings(graph)

    baseline =
      repo_root
      |> Path.join("docs/architecture/dependency-baseline.txt")
      |> DependencyBoundary.read_baseline!()

    result = DependencyBoundary.compare(findings, baseline)
    print_dependency_details(result, Keyword.get(opts, :summary, false))

    counts = Enum.frequencies_by(findings, & &1.kind)

    Mix.shell().info(
      "Architecture dependency baseline: " <>
        "#{Map.get(counts, :root_facade, 0)} root-facade edges, " <>
        "#{Map.get(counts, :persistence_schema, 0)} schema edges, " <>
        "#{Map.get(counts, :context_schema, 0)} cross-context row edges, " <>
        "#{Map.get(counts, :context_direction, 0)} reverse-context edges, " <>
        "#{Map.get(counts, :plane_direction, 0)} reverse-plane edges, " <>
        "#{Map.get(counts, :plane_internal, 0)} cross-plane internal edges, " <>
        "#{Map.get(counts, :web_catch_all, 0)} web catch-all edges, " <>
        "#{Map.get(counts, :web_legacy_adapter, 0)} API legacy-adapter edges, " <>
        "#{Map.get(counts, :unclassified_plane, 0)} unclassified plane modules, " <>
        "#{Map.get(counts, :unclassified_context, 0)} unclassified context modules, " <>
        "#{length(result.new)} new, #{length(result.resolved)} resolved; " <>
        "owner #{result.owner}, review by #{result.review_by}."
    )

    result
  end

  defp print_dependency_details(_result, true), do: :ok

  defp print_dependency_details(result, false) do
    Enum.each(result.new, fn finding ->
      Mix.shell().info("error: new " <> DependencyBoundary.format_finding(finding))
    end)

    Enum.each(result.resolved, fn fingerprint ->
      Mix.shell().info("error: remove resolved dependency baseline: " <> fingerprint)
    end)
  end

  defp load_xref_graph!(repo_root, opts) do
    build_path = compile_web_project!(repo_root)
    current = CompiledGraph.load!(repo_root, build_path)

    Mix.shell().info(
      "Architecture production coverage: #{map_size(current)} domain and web sources, " <>
        "#{Enum.sum(Enum.map(current, fn {_, references} -> map_size(references) end))} dependencies, MIX_ENV=#{Mix.env()}."
    )

    case opts[:xref_json] do
      nil -> current
      path -> path |> File.read!() |> Jason.decode!() |> CompiledGraph.validate_prepared!(current)
    end
  end

  defp compile_web_project!(repo_root) do
    # Compiling this dependent project also compiles Cadence. Keep the caller's
    # environment and build configuration; never substitute the empty workspace
    # root manifest or switch to a development graph.
    project_command!(repo_root, ["compile", "--warnings-as-errors"])
    marker = "CADENCE_ARCHITECTURE_BUILD_PATH:"

    output =
      project_command!(repo_root, [
        "run",
        "--no-start",
        "--no-compile",
        "-e",
        "IO.puts(\"#{marker}\" <> Mix.Project.build_path())"
      ])

    case output
         |> String.split("\n", trim: true)
         |> Enum.filter(&String.starts_with?(&1, marker)) do
      [line] -> String.replace_prefix(line, marker, "")
      _ -> Mix.raise("Could not locate the compiled web project build path.")
    end
  end

  defp project_command!(repo_root, arguments) do
    {output, status} =
      System.cmd("mix", arguments,
        cd: Path.join(repo_root, "apps/cadence_web"),
        env: [
          {"MIX_ENV", Atom.to_string(Mix.env())},
          {"MIX_TARGET", Atom.to_string(Mix.target())}
        ],
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("Could not inspect compiled production sources:\n" <> output)
    output
  end

  defp maybe_raise_dependency_failure!(:skipped), do: :ok

  defp maybe_raise_dependency_failure!(result) do
    cond do
      result.expired? ->
        Mix.raise("Architecture dependency baseline review date has expired.")

      result.new != [] ->
        Mix.raise("Architecture dependency check found #{length(result.new)} new edge(s).")

      result.resolved != [] ->
        Mix.raise(
          "Architecture dependency baseline retains #{length(result.resolved)} resolved edge(s)."
        )

      true ->
        :ok
    end
  end
end
