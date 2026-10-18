defmodule Cadence.Telemetry.HistoricalWorkflowGroupPolicyTest do
  use Cadence.DataCase, async: false

  alias Cadence.Jobs
  alias Cadence.Reads.Telemetry
  alias Cadence.Telemetry.DataManagement

  setup do
    persist_mission_scope("org-policy", "mission-policy")
    :ok
  end

  test "group review and execution exclude an item whose job already exists" do
    request("one", "group")
    request("two", "group")
    assert {:ok, approved, [ok: nil, ok: nil]} = transition(:approved)

    assert {:ok, existing} =
             Jobs.enqueue(:telemetry_historical_data_workflow, "mission-policy", "one", %{})

    assert {:ok, review} =
             DataManagement.historical_data_workflow_group_transition_review(
               :backfill,
               :started,
               "group",
               attrs()
             )

    assert Enum.map(review.sources, & &1.backfill_run_id) == ["two"]

    assert review.blocked == [
             Enum.find(approved, &(&1.backfill_run_id == "one")).backfill_lifecycle_event_id
           ]

    assert {:ok, [started], [ok: created]} = transition(:started)
    assert started.backfill_run_id == "two"
    assert created.run_id == "two"
    assert created.job_id != existing.job_id

    assert {:ok, events} =
             Telemetry.fetch_backfill_lifecycle_group_events("mission-policy", "group",
               organization_id: "org-policy"
             )

    assert Enum.count(events, &(&1.event_type == :backfill_started)) == 1
    assert {:error, {:no_eligible_items, :started}} = transition(:started)
  end

  test "fresh execution policy observes a job created after review" do
    request("one", "group")
    assert {:ok, [_], [_]} = transition(:approved)

    assert {:ok, %{sources: [_]}} =
             DataManagement.historical_data_workflow_group_transition_review(
               :backfill,
               :started,
               "group",
               attrs()
             )

    assert {:ok, _} =
             Jobs.enqueue(:telemetry_historical_data_workflow, "mission-policy", "one", %{})

    assert {:error, {:no_eligible_items, :started}} = transition(:started)

    assert {:ok, events} =
             Telemetry.fetch_backfill_lifecycle_group_events("mission-policy", "group",
               organization_id: "org-policy"
             )

    refute Enum.any?(events, &(&1.event_type == :backfill_started))
  end

  test "explicit event lists cannot import foreign evidence into an action context" do
    event = request("one", "group")

    for context <- [
          %{attrs() | mission_id: "foreign-mission"},
          %{attrs() | organization_id: "foreign-org"}
        ] do
      assert {:error, :historical_workflow_group_scope_mismatch} =
               DataManagement.record_historical_data_workflow_group_transition(
                 :backfill,
                 :approved,
                 [event],
                 context
               )
    end
  end

  defp attrs,
    do: %{
      organization_id: "org-policy",
      mission_id: "mission-policy",
      actor_id: "operator",
      actor_kind: "operator"
    }

  defp transition(stage),
    do:
      DataManagement.record_historical_data_workflow_group_transition(
        :backfill,
        stage,
        "group",
        attrs(),
        dashboard_runtime_invalidation?: false
      )

  defp request(run, group) do
    assert {:ok, event} =
             DataManagement.record_historical_data_workflow_event(
               :backfill,
               :requested,
               Map.merge(attrs(), %{
                 backfill_run_id: run,
                 realm: :backfill,
                 data_source_id: "source",
                 binding_id: "binding",
                 point_id: run,
                 payload: %{
                   "request_group_id" => group,
                   "request_item_index" => if(run == "one", do: 1, else: 2),
                   "request_item_count" => 2
                 }
               }),
               dashboard_runtime_invalidation?: false
             )

    event
  end
end
