defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionCommandsTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionCommands
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionParams

  @opts [dashboard_runtime_invalidation?: false]
  @scope %{organization_id: "org-dashboard-revision-command", user: %{id: "operator-revision"}}
  @mission %{mission_id: "mission-dashboard-revision-command"}

  test "applies an observation identity decision and returns the audit event" do
    envelope = envelope(sample_id: "sample-revision-command")
    assert :ok = ObservationIdentityStates.record_envelopes([envelope])

    params =
      RevisionDecisionParams.new(%{
        "observation_identity_id" => envelope.observation_identity_id,
        "decision" => "mark_conflict",
        "realm" => "flight",
        "data_source_id" => "managed_questdb_primary",
        "source_binding_id" => "default_flight_telemetry",
        "decision_reason" => "operator_marked_from_dashboard",
        "source_decision_event_id" => "decision-event-source",
        "source_decision" => "mark_advisory",
        "source_target" => "comparison_finding",
        "source_target_id" => "placement-1",
        "source_link_label" => "Comparison finding",
        "comparison_state" => "increased",
        "dashboard_limit_mode" => "compare",
        "comparison_delta" => "+2",
        "primary_sample_id" => "sample-primary-1",
        "compare_sample_id" => "sample-compare-1",
        "primary_data_view" => "all_revisions",
        "compare_data_view" => "canonical",
        "widget_id" => "widget-1",
        "widget_title" => "Counter",
        "authority" => "operator"
      })

    assert {:ok, state, event} =
             RevisionDecisionCommands.apply_decision(params, @scope, @mission, @opts)

    assert state.observation_identity_id == envelope.observation_identity_id
    assert state.validity_state == :conflict
    assert state.decision_reason == "operator_marked_from_dashboard"

    assert event.observation_identity_id == envelope.observation_identity_id
    assert event.decision == :mark_conflict
    assert event.decision_reason == "operator_marked_from_dashboard"
    assert event.actor_id == "operator-revision"
    assert event.actor_kind == "operator"
    assert event.evidence_ref["kind"] == "dashboard_revision_decision"
    assert event.evidence_ref["id"] == "decision-event-source"
    assert event.evidence_ref["source_target"] == "comparison_finding"
    assert event.evidence_ref["source_target_id"] == "placement-1"
    assert event.evidence_ref["source_link_label"] == "Comparison finding"
    assert event.evidence_ref["dashboard_context"] == %{"dashboard_limit_mode" => "compare"}
    assert event.evidence_ref["correction_workflow"]["authority"] == "operator"

    assert event.evidence_ref["comparison_finding"] == %{
             "placement_id" => "placement-1",
             "state" => "increased",
             "delta" => "+2",
             "primary_sample_id" => "sample-primary-1",
             "compare_sample_id" => "sample-compare-1",
             "primary_data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "widget_id" => "widget-1",
             "widget_title" => "Counter"
           }
  end

  defp envelope(overrides) do
    {:ok, context} =
      WriteContext.new(
        organization_id: @scope.organization_id,
        mission_id: @mission.mission_id,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        recorded_at: ~U[2026-06-22 12:00:00Z],
        metadata: %{}
      )

    {:ok, envelope} =
      ObservationEnvelope.from_sample(
        context,
        sample(Keyword.fetch!(overrides, :sample_id), ~U[2026-06-22 11:00:00Z])
      )

    envelope
  end

  defp sample(sample_id, generation_time) do
    %Sample{
      sample_id: sample_id,
      mission_id: @mission.mission_id,
      spacecraft_id: "sc-1",
      point_id: "HK.counter",
      point_name: "HK.counter",
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: 42,
      engineering_value: 42,
      quality_state: :good,
      generation_time: generation_time,
      receipt_time: DateTime.add(generation_time, 3, :second),
      provenance: %{}
    }
  end
end
