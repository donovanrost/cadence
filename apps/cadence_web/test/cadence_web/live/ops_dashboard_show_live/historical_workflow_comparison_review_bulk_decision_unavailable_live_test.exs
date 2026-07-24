defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowComparisonReviewBulkDecisionUnavailableLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

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

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  describe "comparison-review bulk revision decision unavailable states" do
    test "explains unavailable bulk comparison decisions when source context is missing" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {_sample, state} =
        persist_revision_sample_identity!(org, mission, "sample-review-missing-source",
          point_id: "HK.counter"
        )

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 1,
                   "open_placement_ids" => ["placement-counter"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
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
                         "primary_revision" => state.canonical_revision
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

      refute has_element?(
               view,
               "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-bulk-decision-unavailable="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-bulk-decision-unavailable-reason="missing_source_context"][data-dashboard-comparison-review-bulk-decision-unavailable-count="1"][data-dashboard-comparison-review-bulk-decision-unavailable-placements="placement-counter"]),
               "Bulk decision unavailable: telemetry source context is missing."
             )

      assert [] =
               Storage.list_observation_identity_decision_events(
                 state.observation_identity_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )
    end

    test "explains unavailable bulk comparison decisions when no findings are actionable" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

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
                   "open_count" => 1,
                   "open_placement_ids" => ["placement-counter"],
                   "open_findings" => %{
                     "schema" => "dashboard_comparison_open_findings.v1",
                     "findings" => [
                       %{
                         "placement_id" => "placement-counter",
                         "title" => "Counter",
                         "state" => "increased",
                         "decision_status" => "unhandled",
                         "primary_data_view" => "all_revisions",
                         "compare_data_view" => "canonical",
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

      refute has_element?(
               view,
               "#dashboard-comparison-review-bulk-decision-form-#{request_event.dashboard_lifecycle_event_id}"
             )

      assert has_element?(
               view,
               ~s([data-dashboard-comparison-review-bulk-decision-unavailable="#{request_event.dashboard_lifecycle_event_id}"][data-dashboard-comparison-review-bulk-decision-unavailable-reason="no_actionable_findings"][data-dashboard-comparison-review-bulk-decision-unavailable-count="0"][data-dashboard-comparison-review-bulk-decision-unavailable-placements=""]),
               "Bulk decision unavailable: no actionable findings."
             )

      assert [] =
               Storage.list_observation_identity_decision_events(
                 "missing-observation-identity",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )
    end
  end
end
