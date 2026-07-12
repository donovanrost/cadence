defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRevisionDecisionLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Persistence.Schemas.{PacketRecordRow, RawEvidenceRow}
  alias Cadence.Protocol.PacketRecord
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

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp element_attribute(html, selector, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    value
  end

  defp persist_revision_sample_identity!(org, mission, sample_id, opts \\ []) do
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
        source_ref: "dashboard-revision-decision-live-test",
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
    tracked_views =
      Process.get(:ops_dashboard_historical_workflow_revision_decision_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_revision_decision_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_revision_decision_view, pid}, fn ->
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

  describe "historical workflow revision decision surfaces" do
    test "applies revision decisions from the revision event inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {sample, initial_state} =
        persist_revision_sample_identity!(org, mission, "sample-dashboard-revision-live")

      assert initial_state.validity_state == :canonical

      assert %Sample{} =
               latest_before_decision =
               Cadence.latest_telemetry_value(
                 org.organization_id,
                 mission.mission_id,
                 "HK.counter",
                 spacecraft_id: sample.spacecraft_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )

      assert latest_before_decision.sample_id == sample.sample_id

      assert {:ok, _state} =
               Cadence.apply_telemetry_observation_identity_decision(
                 initial_state.observation_identity_id,
                 "mark_canonical",
                 %{
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :flight,
                   data_source_id: "managed_questdb_primary",
                   binding_id: "default_flight_telemetry",
                   canonical_observation_id: initial_state.canonical_observation_id,
                   canonical_sample_id: initial_state.canonical_sample_id,
                   canonical_revision: initial_state.canonical_revision,
                   decision_reason: "prior_dashboard_canonical_review",
                   authority: "operator",
                   requested_by: "dashboard",
                   operator_id: "operator-source",
                   evidence_ref: %{
                     "kind" => "dashboard_revision_marker",
                     "id" => "source-marker-1",
                     "source_target" => "comparison_finding",
                     "source_target_id" => "placement-1",
                     "source_link_label" => "Comparison finding"
                   }
                 },
                 dashboard_runtime_invalidation?: false
               )

      assert %Sample{} =
               latest_after_source_decision =
               Cadence.latest_telemetry_value(
                 org.organization_id,
                 mission.mission_id,
                 "HK.counter",
                 spacecraft_id: sample.spacecraft_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry"
               )

      assert latest_after_source_decision.sample_id == sample.sample_id

      [source_event] =
        Storage.list_observation_identity_decision_events(
          initial_state.observation_identity_id,
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_revision_decision_event&selected_id=#{source_event.decision_event_id}&time_mode=replay_run&replay_run_id=revision-replay-1&data_view=all_revisions&limit_mode=compare"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-controls[data-revision-decision-observation-identity="#{initial_state.observation_identity_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-dashboard-limit-mode[value="compare"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-dashboard-time-mode[value="replay_run"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-dashboard-replay-run-id[value="revision-replay-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-revision-decision-dashboard-data-view[value="all_revisions"])
             )

      view
      |> form("#dashboard-revision-decision-form", %{
        "revision_decision" => %{
          "decision" => "mark_conflict",
          "decision_reason" => "operator_marked_conflict_from_dashboard",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      result_path = assert_patch(view)
      assert result_path =~ "selected_target=telemetry_revision_decision_event"
      assert result_path =~ "time_mode=replay_run"
      assert result_path =~ "replay_run_id=revision-replay-1"
      assert result_path =~ "selected_data_view=all_revisions"
      assert result_path =~ "limit_mode=compare"

      decision_events =
        Storage.list_observation_identity_decision_events(
          initial_state.observation_identity_id,
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "default_flight_telemetry"
        )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="revision_decision"][data-data-link-action-outcome-status="ok"][data-data-link-action-outcome-reason="revision_decision_applied"][data-data-link-action-outcome-decision="mark_conflict"][data-data-link-action-outcome-dashboard-time-mode="replay_run"][data-data-link-action-outcome-dashboard-replay-run-id="revision-replay-1"][data-data-link-action-outcome-dashboard-data-view="all_revisions"][data-data-link-action-outcome-dashboard-limit-mode="compare"]),
               "Telemetry revision decision applied."
             )

      metadata =
        view
        |> render()
        |> element_attribute(
          "#dashboard-data-link-action-outcome",
          "data-data-link-action-outcome-metadata"
        )
        |> Jason.decode!()

      applied_event =
        Enum.find(
          decision_events,
          &(&1.decision_event_id == metadata["result_event_id"])
        )

      assert result_path =~ "selected_id=#{applied_event.decision_event_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-result-event-id="#{applied_event.decision_event_id}"][data-data-link-action-outcome-target-event-id="#{applied_event.decision_event_id}"][data-data-link-action-outcome-target-observation-identity-id="#{initial_state.observation_identity_id}"])
             )

      assert applied_event.decision == :mark_conflict
      assert applied_event.decision_reason == "operator_marked_conflict_from_dashboard"
      assert applied_event.evidence_ref["kind"] == "dashboard_revision_decision"
      assert applied_event.evidence_ref["id"] == source_event.decision_event_id
      assert applied_event.evidence_ref["source_target"] == "telemetry_revision_decision_event"
      assert applied_event.evidence_ref["source_target_id"] == source_event.decision_event_id

      assert applied_event.evidence_ref["dashboard_context"] == %{
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "revision-replay-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "compare"
             }

      assert applied_event.previous_state["validity_state"] == "canonical"
      assert applied_event.new_state["validity_state"] == "conflict"
      assert applied_event.previous_state["canonical_sample_id"] == sample.sample_id
      assert applied_event.new_state["canonical_sample_id"] == sample.sample_id

      assert {:ok, applied_state} =
               Storage.fetch_observation_identity_state(initial_state.observation_identity_id)

      assert applied_state.validity_state == :conflict
      assert applied_state.decision_event_id == applied_event.decision_event_id
      assert applied_state.decision_reason == "operator_marked_conflict_from_dashboard"

      assert applied_state.payload["decision"]["evidence_ref"]["dashboard_context"] == %{
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "revision-replay-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "compare"
             }

      refute Cadence.latest_telemetry_value(org.organization_id, mission.mission_id, "HK.counter",
               spacecraft_id: sample.spacecraft_id,
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               binding_id: "default_flight_telemetry"
             )

      assert metadata == %{
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "revision-replay-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "compare",
               "decision" => "mark_conflict",
               "result_event_id" => applied_event.decision_event_id,
               "target_event_id" => applied_event.decision_event_id,
               "target_observation_identity_id" => initial_state.observation_identity_id
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Revision decision event"]),
               applied_event.decision_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Previous validity state"]),
               "canonical"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="New validity state"]),
               "conflict"
             )

      copied_path =
        view
        |> render()
        |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

      assert copied_path =~ "selected_target=telemetry_revision_decision_event"
      assert copied_path =~ "selected_id=#{applied_event.decision_event_id}"
      assert copied_path =~ "time_mode=replay_run"
      assert copied_path =~ "replay_run_id=revision-replay-1"
      assert copied_path =~ "selected_data_view=all_revisions"
      assert copied_path =~ "limit_mode=compare"
    end
  end
end
