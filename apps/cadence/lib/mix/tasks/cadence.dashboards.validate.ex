defmodule Mix.Tasks.Cadence.Dashboards.Validate do
  @moduledoc """
  Validates Dashboard Documents or governed dashboard export bundles for CI.

  ## Usage

      mix cadence.dashboards.validate path/to/dashboard.json [more.json]
  """

  use Mix.Task

  alias Cadence.Dashboards.AsCode

  @shortdoc "Validate dashboard-as-code artifacts"

  @impl true
  def run([]), do: Mix.raise("Provide at least one dashboard JSON path.")

  def run(paths) do
    Mix.Task.run("compile")

    results = Enum.map(paths, &{&1, AsCode.validate_file(&1)})

    Enum.each(results, fn
      {path, {:ok, result}} ->
        Mix.shell().info(
          "valid #{path}: #{result.name} (#{result.dashboard_id}) schema v#{result.schema_version}"
        )

      {path, {:error, error}} ->
        Mix.shell().error("invalid #{path}: #{inspect(error.reason)}")
    end)

    failures = Enum.count(results, fn {_path, result} -> match?({:error, _error}, result) end)

    if failures > 0 do
      Mix.raise("Dashboard-as-code validation failed for #{failures} artifact(s).")
    end
  end
end
