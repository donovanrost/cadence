defmodule Cadence.ContactPlanning.FleetRepairInputs do
  @moduledoc """
  Reconstructs the immutable repair input handed from contact execution to
  fleet planning.

  Repair orchestration records exact source-plan and locked-snapshot evidence
  on the planning run. The planner uses this service to validate that evidence
  without depending on the Contacts-owned repair workflow.
  """

  alias Cadence.ContactPlanning.{ContactPlans, FleetPlanningRun}

  @spec locked_commitments(FleetPlanningRun.t()) :: {:ok, [struct()]} | {:error, term()}
  def locked_commitments(%FleetPlanningRun{trigger_kind: trigger})
      when trigger != :repair,
      do: {:ok, []}

  def locked_commitments(%FleetPlanningRun{} = run) do
    expected =
      run.input_document
      |> get_in(["repair", "locked_commitments"])
      |> List.wrap()

    with {:ok, version} <-
           ContactPlans.fetch_version(
             run.organization_id,
             run.mission_id,
             run.source_contact_plan_id,
             run.source_contact_plan_version
           ),
         :ok <- exact_source_version(run, version) do
      snapshots =
        ContactPlans.selected_snapshots(
          run.organization_id,
          run.mission_id,
          run.source_contact_plan_id,
          run.source_contact_plan_version
        )

      exact_locked_snapshots(expected, snapshots)
    end
  end

  defp exact_source_version(run, version) do
    expected = get_in(run.input_document, ["repair", "source_plan_content_sha256"])

    if version.content_sha256 == expected,
      do: :ok,
      else: {:error, :fleet_repair_source_plan_drift}
  end

  defp exact_locked_snapshots(expected, snapshots) do
    by_id = Map.new(snapshots, &{&1.contact_opportunity_snapshot_id, &1})

    expected
    |> Enum.reduce_while({:ok, []}, fn ref, {:ok, locked} ->
      snapshot_id = ref["contact_opportunity_snapshot_id"]
      expected_hash = ref["content_sha256"]

      case by_id[snapshot_id] do
        %{content_sha256: ^expected_hash} = snapshot ->
          {:cont, {:ok, [snapshot | locked]}}

        nil ->
          {:halt, {:error, :fleet_repair_locked_snapshot_not_found}}

        _snapshot ->
          {:halt, {:error, :fleet_repair_locked_snapshot_drift}}
      end
    end)
    |> case do
      {:ok, locked} ->
        {:ok, Enum.sort_by(locked, &{&1.starts_at, &1.contact_opportunity_snapshot_id})}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
