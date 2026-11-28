defmodule Cadence.Jobs.RetentionTest do
  use Cadence.DataCase, async: false

  alias Cadence.Jobs
  alias Cadence.Jobs.{BackgroundJobRow, Retention}
  alias Cadence.Persistence.Retention.Sweeper

  @now ~U[2026-11-28 12:00:00Z]

  test "retention index covers every terminal job, whatever its type" do
    %{rows: [[definition]]} =
      Repo.query!(
        "SELECT pg_get_indexdef('background_jobs_terminal_completed_at_idx'::regclass)",
        []
      )

    predicate = definition |> String.split(" WHERE ", parts: 2) |> List.last()

    refute predicate =~ "job_type"

    assert predicate
           |> then(&Regex.scan(~r/'([^']+)'/, &1, capture: :all_but_first))
           |> List.flatten()
           |> Enum.sort() == ["completed", "failed"]
  end

  test "sweeps old terminal jobs of every type by completion time and keeps live, unknown and recent jobs" do
    mission = "mission-retention-#{Ecto.UUID.generate()}"
    persist_mission_scope("org-retention-#{Ecto.UUID.generate()}", mission)

    old = DateTime.add(@now, -15 * 86_400)
    recent = DateTime.add(@now, -13 * 86_400)

    old_completed = job!(mission, "completed", old, old)
    old_failed = job!(mission, "failed", old, old)
    old_queued = job!(mission, "queued", old, nil)
    old_running = job!(mission, "running", old, nil)
    old_unknown = job!(mission, "outcome_unknown", old, old)

    old_workflow =
      job!(mission, "completed", old, old, :telemetry_historical_data_workflow)

    recent_completed = job!(mission, "completed", old, recent)
    recent_failed = job!(mission, "failed", old, recent)

    assert %{rows: 3, stopped: :done} =
             Sweeper.sweep(Retention, nil, now: @now, chunk_rows: 1, pause_ms: 0)

    for job <- [old_completed, old_failed, old_workflow] do
      assert {:error, :job_not_found} = Jobs.fetch_job(job.job_id)
    end

    for job <- [
          old_queued,
          old_running,
          old_unknown,
          recent_completed,
          recent_failed
        ] do
      assert {:ok, _} = Jobs.fetch_job(job.job_id)
    end
  end

  defp job!(mission, status, inserted_at, completed_at, type \\ :mission_event_rebuild) do
    {:ok, job} = Jobs.enqueue(type, mission, Ecto.UUID.generate(), %{})

    {1, _rows} =
      Repo.update_all(
        from(row in BackgroundJobRow, where: row.job_id == ^job.job_id),
        set: [status: status, inserted_at: inserted_at, completed_at: completed_at]
      )

    job
  end
end
