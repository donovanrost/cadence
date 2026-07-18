defmodule Mix.Tasks.Cadence.Architecture.Check do
  @moduledoc """
  Reports source-size pressure against the active architecture review.

  ## Usage

      mix cadence.architecture.check

  ## Options

    * `--production-file-limit` - production `.ex` line limit, defaults to 1000
    * `--test-file-limit` - test source line limit, defaults to 1500
    * `--test-function-limit` - individual `test` block line limit, defaults to 300
    * `--summary` - print counts without listing every finding
    * `--strict` - fail when any finding is present
  """

  use Mix.Task

  alias Cadence.Architecture.SourceSize

  @shortdoc "Report architecture source-size pressure"

  @switches [
    production_file_limit: :integer,
    test_file_limit: :integer,
    test_function_limit: :integer,
    summary: :boolean,
    strict: :boolean
  ]

  @impl true
  def run(args) do
    {opts, remaining, invalid} = OptionParser.parse(args, strict: @switches)
    validate_args!(remaining, invalid)
    validate_limits!(opts)

    findings = SourceSize.scan(SourceSize.repo_root!(), opts)

    unless opts[:summary] do
      Enum.each(findings, fn finding ->
        Mix.shell().info("warning: " <> SourceSize.format_finding(finding))
      end)
    end

    Mix.shell().info(summary(findings))

    if Keyword.get(opts, :strict, false) and findings != [] do
      Mix.raise("Architecture source-size check found #{length(findings)} violation(s).")
    end
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
end
