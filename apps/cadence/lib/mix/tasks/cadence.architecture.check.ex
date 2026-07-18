defmodule Mix.Tasks.Cadence.Architecture.Check do
  @moduledoc """
  Reports source-size pressure and enforces ratcheted dependency boundaries.

  ## Usage

      mix cadence.architecture.check

  ## Options

    * `--production-file-limit` - production `.ex` line limit, defaults to 1000
    * `--test-file-limit` - test source line limit, defaults to 1500
    * `--test-function-limit` - individual `test` block line limit, defaults to 300
    * `--xref-json` - read a prepared core xref JSON graph instead of generating one
    * `--skip-dependencies` - run only the advisory source-size diagnostic
    * `--summary` - print counts without listing every finding
    * `--strict` - fail when any source-size finding is present
  """

  use Mix.Task

  alias Cadence.Architecture.{DependencyBoundary, SourceSize}

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
    case opts[:xref_json] do
      nil -> generate_xref_graph!(repo_root)
      path -> path |> File.read!() |> Jason.decode!()
    end
  end

  defp generate_xref_graph!(repo_root) do
    output_path =
      Path.join(
        System.tmp_dir!(),
        "cadence-xref-#{System.unique_integer([:positive, :monotonic])}.json"
      )

    try do
      {_output, status} =
        System.cmd(
          "mix",
          ["xref", "graph", "--format", "json", "--output", output_path],
          cd: Path.join(repo_root, "apps/cadence"),
          env: [{"MIX_ENV", "dev"}],
          stderr_to_stdout: true
        )

      if status != 0 do
        Mix.raise("Could not generate the core xref dependency graph.")
      end

      output_path
      |> File.read!()
      |> Jason.decode!()
    after
      File.rm(output_path)
    end
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
