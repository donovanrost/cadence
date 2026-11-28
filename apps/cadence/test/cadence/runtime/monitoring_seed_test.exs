defmodule Cadence.Runtime.PartitionOwner.MonitoringSeedTest do
  @moduledoc "The seed reads the mission's active alarm states for the plan's policies."
  use Cadence.DataCase, async: true

  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.PartitionOwner.MonitoringSeed
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.SemanticRuntime.{MonitoringPlan, Scope, State}

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-monitoring-seed-#{suffix}"
    mission_id = "mission-monitoring-seed-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "seeds the plan's policies, active states only, in every spacecraft scope", ctx do
    alarm_state!(ctx, "sc-001", "policy:critical", "critical")
    alarm_state!(ctx, "sc-001", "policy:normal", "normal")
    alarm_state!(ctx, "sc-002", "policy:other-craft", "warning")
    alarm_state!(ctx, "sc-001", "policy:not-planned", "warning")

    plan = %{
      algorithms: [],
      monitoring:
        Enum.map(
          ["policy:critical", "policy:normal", "policy:other-craft"],
          &MonitoringPlan.new(%{policy_id: &1, parameter_id: "parameter:" <> &1})
        )
    }

    assert Enum.sort(MonitoringSeed.entries(%{mission_id: ctx.mission_id}, plan)) == [
             {Scope.new(ctx.mission_id, "sc-001"), "policy:critical", :critical},
             {Scope.new(ctx.mission_id, "sc-002"), "policy:other-craft", :warning}
           ]
  end

  test "another mission's alarms and a plan without monitoring seed nothing", ctx do
    alarm_state!(ctx, "sc-001", "policy:critical", "critical")

    plan = %{
      algorithms: [],
      monitoring: [MonitoringPlan.new(%{policy_id: "policy:critical", parameter_id: "p"})]
    }

    assert MonitoringSeed.entries(%{mission_id: "another-mission"}, plan) == []
    assert MonitoringSeed.entries(%{mission_id: ctx.mission_id}, %{plan | monitoring: []}) == []
  end

  test "seeds only the policies the recovered state has no entry for (#443)", ctx do
    alarm_state!(ctx, "sc-001", "policy:kept", "critical")
    alarm_state!(ctx, "sc-001", "policy:new", "warning")

    plan = %{
      algorithms: [],
      monitoring:
        Enum.map(
          ["policy:kept", "policy:new"],
          &MonitoringPlan.new(%{policy_id: &1, parameter_id: "parameter:" <> &1})
        )
    }

    scope = Scope.new(ctx.mission_id, "sc-001")
    carried = %{effective_state: :normal, candidate_state: :normal}
    state = %State{monitoring_state: %{{scope, "policy:kept"} => carried}}

    assert {:ok, seeded} =
             MonitoringSeed.maybe_seed(%{mission_id: ctx.mission_id}, key(), plan, state)

    # The carried policy keeps what the partition remembered, even where the table says otherwise.
    assert seeded.monitoring_state[{scope, "policy:kept"}] == carried
    assert %{effective_state: :warning} = seeded.monitoring_state[{scope, "policy:new"}]

    # With an entry for every policy there is nothing to read or seed.
    full = %State{
      monitoring_state: Map.put(seeded.monitoring_state, {scope, "policy:new"}, carried)
    }

    assert {:ok, ^full} =
             MonitoringSeed.maybe_seed(%{mission_id: ctx.mission_id}, key(), plan, full)
  end

  defp key, do: PartitionKey.new(%{affinity: :source_endpoint, value: "seed-test"})

  defp alarm_state!(ctx, spacecraft_id, policy_id, effective_state) do
    at = ~U[2026-11-15 12:00:00.000000Z]

    %{
      organization_id: ctx.organization_id,
      mission_id: ctx.mission_id,
      spacecraft_id: spacecraft_id,
      parameter_id: "parameter:" <> policy_id,
      policy_id: policy_id,
      evaluation_id: "evaluation:" <> policy_id,
      transition_id: "transition:" <> policy_id,
      effective_state: effective_state,
      generation_time: at,
      receipt_time: at
    }
    |> LatestAlarmStateRow.changeset()
    |> Repo.insert!()
  end
end
