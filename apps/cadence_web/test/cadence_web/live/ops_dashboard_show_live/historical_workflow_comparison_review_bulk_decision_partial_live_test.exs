defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowComparisonReviewBulkDecisionPartialLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Ingress.RawEvidence
  alias Cadence.IngressArchive.Postgres.RawEvidenceRow
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow
  alias Cadence.Repo
  alias Cadence.Telemetry.{Sample, Storage}
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp persist_revision_sample_identity!(org, mission, sample_id, opts) do
    point_id = Keyword.get(opts, :point_id, "HK.counter")
    sample = revision_sample(mission, sample_id, ~U[2026-06-22 11:00:00Z], opts)

    persist_sample_scope!(sample)

    assert :ok =
             Storage.persist_samples([sample],
               organization_id: org.organization_id,
               recorded_at: ~U[2026-06-22 12:00:00Z],
               dashboard_runtime_invalidation?: false
             )

    [state] =
      Storage.list_observation_identity_states(mission.mission_id,
        organization_id: org.organization_id,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        point_id: point_id
      )

    {sample, state}
  end

  defp revision_sample(mission, sample_id, generation_time, opts) do
    point_id = Keyword.get(opts, :point_id, "HK.counter")

    telemetry_sample(
      mission,
      sample_id,
      point_id,
      generation_time,
      DateTime.add(generation_time, 3, :second),
      raw_value: 42,
      engineering_value: 42,
      spacecraft_id: "sc-dashboard-revision",
      packet_definition_id: "packet-def-dashboard-revision",
      packet_id: "packet-dashboard-revision-#{sample_id}",
      evidence_id: "evidence-dashboard-revision-#{sample_id}"
    )
  end

  defp persist_sample_scope!(%Sample{} = sample) do
    raw_evidence =
      RawEvidence.new(%{
        evidence_id: sample.evidence_id,
        mission_id: sample.mission_id,
        spacecraft_id: sample.spacecraft_id,
        protocol_family: :space_packet,
        direction: :downlink,
        raw: <<0, 1, 2, 3>>,
        source_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        source_ref: "dashboard-live-test",
        metadata: %{}
      })

    packet_record = %PacketRecord{
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 1,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<0, 1, 2, 3>>,
      source_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: %{}
    }

    {:ok, _raw_evidence_row} = Repo.insert(RawEvidenceRow.changeset(raw_evidence))
    {:ok, _packet_record_row} = Repo.insert(PacketRecordRow.changeset(packet_record))

    :ok
  end

  defp telemetry_sample(mission, sample_id, point_id, generation_time, receipt_time, opts) do
    %Sample{
      sample_id: sample_id,
      mission_id: mission.mission_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id, "sc-dashboard-telemetry"),
      point_id: point_id,
      point_name: point_id,
      packet_definition_id:
        Keyword.get(opts, :packet_definition_id, "packet-def-dashboard-telemetry"),
      packet_definition_version: 1,
      packet_id: Keyword.get(opts, :packet_id, "packet-dashboard-telemetry"),
      evidence_id: Keyword.get(opts, :evidence_id, "evidence-dashboard-telemetry"),
      raw_value: Keyword.fetch!(opts, :raw_value),
      engineering_value: Keyword.fetch!(opts, :engineering_value),
      quality_state: :good,
      generation_time: generation_time,
      receipt_time: receipt_time,
      provenance: Keyword.get(opts, :provenance, %{})
    }
  end

  test "shows partial failure outcome for bulk comparison review decisions" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {_sample, state} =
      persist_revision_sample_identity!(org, mission, "sample-review-bulk-partial",
        point_id: "HK.counter"
      )

    missing_observation_identity_id = "missing-observation-identity-partial"

    source_context = %{
      "realm" => "flight",
      "data_source_id" => "managed_questdb_primary",
      "source_binding_id" => "default_flight_telemetry"
    }

    assert {:ok, request_event} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 2,
                 "open_placement_ids" => ["placement-counter", "placement-missing"],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "runtime_query" => source_context,
                   "findings" => [
                     %{
                       "placement_id" => "placement-counter",
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" => state.observation_identity_id,
                       "primary_sample_id" => state.canonical_sample_id,
                       "primary_observation_identity_id" => state.observation_identity_id,
                       "primary_observation_id" => state.canonical_observation_id,
                       "primary_revision" => state.canonical_revision,
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     },
                     %{
                       "placement_id" => "placement-missing",
                       "title" => "Missing identity",
                       "state" => "missing",
                       "decision_status" => "unhandled",
                       "observation_identity_id" => missing_observation_identity_id,
                       "primary_observation_identity_id" => missing_observation_identity_id,
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    path =
      show_path(mission, dashboard) <>
        "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

    {:ok, view, _html} = live(conn, path)
    render_dashboard_async(view)

    presentation = comparison_request_presentation(view, request_event)
    bulk_form = presentation["actions"]["bulk_form"]

    assert %{
             "data-dashboard-comparison-review-bulk-decision-count" => "2",
             "data-dashboard-comparison-review-bulk-decision-placements" =>
               "placement-counter,placement-missing"
           } = bulk_form["attrs"]

    render_submit(
      view,
      bulk_form["attrs"]["phx-submit"],
      form_payload(bulk_form)
    )

    assert_patch(view)

    request_event_id = request_event.dashboard_lifecycle_event_id
    action = comparison_review_action_presentation(view)

    assert %{
             "data-dashboard-comparison-review-action" => "comparison_review_bulk_decision",
             "data-dashboard-comparison-review-action-status" => "degraded",
             "data-dashboard-comparison-review-action-source-request-id" => ^request_event_id,
             "data-dashboard-comparison-review-action-workflow-id" => ^request_event_id,
             "data-dashboard-comparison-review-action-requested" => "2",
             "data-dashboard-comparison-review-action-applied" => "1",
             "data-dashboard-comparison-review-action-failed" => "1"
           } = action["root"]["attrs"]

    assert action["header"]["title"]["text"] == "Comparison Review Action"

    assert action["header"]["message"]["text"] ==
             "Comparison review decisions applied to 1 findings; 1 failed."

    assert action["header"]["status"]["text"] == "Partial"

    action_metadata =
      action["root"]["attrs"]["data-dashboard-comparison-review-action-metadata"]
      |> Jason.decode!()

    assert action_metadata["requested"] == "2"
    assert action_metadata["applied"] == "1"
    assert action_metadata["failed"] == "1"

    assert action_metadata["source_request_event_id"] ==
             request_event.dashboard_lifecycle_event_id

    assert action_metadata["workflow_id"] == request_event.dashboard_lifecycle_event_id

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: "managed_questdb_primary",
      binding_id: "default_flight_telemetry"
    ]

    [event] =
      Storage.list_observation_identity_decision_events(
        state.observation_identity_id,
        query_opts
      )

    assert event.decision == :mark_conflict
    assert event.decision_reason == "dashboard_comparison_review_mark_conflict"
    assert event.actor_id == user.user_id
    assert event.evidence_ref["placement_id"] == "placement-counter"

    assert event.evidence_ref["bulk_workflow_item"] == %{
             "kind" => "telemetry_correction_authority_workflow_item",
             "workflow_id" => request_event.dashboard_lifecycle_event_id,
             "item_index" => 1,
             "item_count" => 2,
             "observation_identity_id" => state.observation_identity_id,
             "selection_kind" => "open_comparison_findings"
           }

    assert Storage.list_observation_identity_decision_events(
             missing_observation_identity_id,
             query_opts
           ) == []

    assert {:ok, updated_state} =
             Storage.fetch_observation_identity_state(state.observation_identity_id)

    assert updated_state.validity_state == :conflict
  end

  defp comparison_request_presentation(rendered, event) do
    event_id = event.dashboard_lifecycle_event_id

    row =
      rendered
      |> activity_timeline_presentation()
      |> get_in(["list", "rows"])
      |> Enum.find(&(&1["key"] == event_id))

    expected_id = "dashboard-activity-#{event_id}"

    assert %{
             "key" => ^event_id,
             "order" => order,
             "presentation" => %{"root" => %{"id" => ^expected_id}}
           } = row

    assert is_integer(order)
    assert row["presentation"] == Jason.decode!(Jason.encode!(row["presentation"]))
    child = row["presentation"]["comparison_review"]["request"]
    assert child["attrs"] == %{"data-name" => "ComparisonReviewActivityDetails"}
    assert child["presentation"]["kind"] == "request"
    child["presentation"]
  end

  defp comparison_review_action_presentation(rendered) do
    rendered
    |> activity_timeline_presentation()
    |> Map.fetch!("comparison_review_action")
  end

  defp activity_timeline_presentation(rendered) do
    vue = LiveVue.Test.get_vue(rendered, id: "dashboard-version-history-panel-component")

    assert Map.take(vue, [:component, :ssr, :class, :handlers]) == %{
             component: "VersionHistoryPanel",
             ssr: false,
             class: "contents",
             handlers: %{}
           }

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    vue.props["presentation"]["activity_timeline"]["presentation"]
  end

  defp form_payload(form) do
    review =
      Map.new(form["hidden_fields"], fn field ->
        name = field["attrs"]["name"]
        key = name |> String.trim_leading("review[") |> String.trim_trailing("]")
        {key, field["attrs"]["value"]}
      end)

    %{"review" => review}
  end
end
