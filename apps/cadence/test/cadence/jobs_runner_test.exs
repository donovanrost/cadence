defmodule Cadence.JobsRunnerTest do
  use ExUnit.Case, async: true

  alias Cadence.Jobs.Job
  alias Cadence.Jobs.Runner

  test "routes a job through the injected handler snapshot" do
    job = job(:catalog_import_run, "catalog-run-alpha")

    runner =
      Runner.new(%{
        catalog_import_run: fn run_id -> {:ok, {:handled, run_id}} end
      })

    assert Runner.dispatch(runner, job) == {:ok, {:handled, "catalog-run-alpha"}}
  end

  test "reports missing and invalid handlers without application environment mutation" do
    job = job(:catalog_import_run, "catalog-run-beta")

    assert Runner.dispatch(Runner.new(%{}), job) ==
             {:error, {:job_handler_not_configured, :catalog_import_run}}

    assert Runner.dispatch(Runner.new(%{catalog_import_run: :invalid}), job) ==
             {:error, {:invalid_job_handler, :catalog_import_run, :invalid}}
  end

  defp job(job_type, run_id) do
    Job.new(%{
      mission_id: "mission-background-jobs",
      job_type: job_type,
      run_id: run_id,
      payload: %{}
    })
  end
end
