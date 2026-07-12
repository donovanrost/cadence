defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowDataManagementLiveTest do
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
  alias Cadence.Telemetry.{HistoryStore, Sample, Storage}
  alias Cadence.Telemetry.HistoryStore.ETS, as: HistoryStoreETS
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
        source_ref: "dashboard-data-management-live-test",
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
      Process.get(:ops_dashboard_historical_workflow_data_management_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_data_management_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_data_management_view, pid}, fn ->
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

  describe "historical workflow data-management surfaces" do
    test "records late-data policy decisions from the lifecycle inspector" do
      previous_history_store = Application.get_env(:cadence, :telemetry_history_store, [])

      Application.put_env(:cadence, :telemetry_history_store,
        module: HistoryStoreETS,
        max_samples_per_point: :infinity
      )

      start_supervised!(HistoryStoreETS)
      HistoryStoreETS.reset()

      on_exit(fn ->
        Application.put_env(:cadence, :telemetry_history_store, previous_history_store)
      end)

      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      selected_sample =
        telemetry_sample(
          mission,
          "dashboard-late-source-sample",
          "HK.counter",
          ~U[2026-06-22 10:10:00Z],
          ~U[2026-06-22 12:05:00Z],
          raw_value: 72,
          engineering_value: 72,
          provenance: %{
            "storage" => %{
              "realm" => "backfill",
              "data_source_id" => "managed_questdb_backfill",
              "binding_id" => "backfill_telemetry"
            }
          }
        )

      assert :ok = persist_sample_scope!(selected_sample)
      assert :ok = HistoryStore.persist_samples([selected_sample])

      assert {:ok, source_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "completed",
                 %{
                   backfill_run_id: "dashboard-late-policy-run",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   receipt_from: ~U[2026-06-22 12:00:00Z],
                   receipt_to: ~U[2026-06-22 12:10:00Z],
                   sample_count: 3,
                   authority: :authoritative,
                   reason: "operator_backfill_completed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{"workflow" => "backfill", "stage" => "completed"}
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{source_event.backfill_lifecycle_event_id}&data_view=all_revisions"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-controls[data-late-data-policy-source-event="#{source_event.backfill_lifecycle_event_id}"][data-late-data-policy-run-id="dashboard-late-policy-run"][data-late-data-policy-execution-mode="sample_execution"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-dashboard-data-view[value="all_revisions"])
             )

      view
      |> form("#dashboard-late-data-policy-form", %{
        "late_data_policy" => %{
          "decision" => "accept",
          "reason" => "operator_accepts_late_data",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      assert_patch(view)

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-late-policy-run"
        )

      policy_event = Enum.find(events, &(&1.event_type == :late_data_accepted))
      assert policy_event.reason == "operator_accepts_late_data"
      assert policy_event.sample_count == 1

      assert %Sample{} = latest = Cadence.latest_telemetry_value(mission.mission_id, "HK.counter")
      assert latest.sample_id == "dashboard-late-source-sample"
      assert latest.raw_value == 72

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="late_data_policy"][data-data-link-action-outcome-status="ok"][data-data-link-action-outcome-reason="late_data_policy_applied"][data-data-link-action-outcome-decision="accept"][data-data-link-action-outcome-execution-mode="sample_execution"][data-data-link-action-outcome-dashboard-time-mode="live"][data-data-link-action-outcome-dashboard-data-view="all_revisions"][data-data-link-action-outcome-dashboard-limit-mode="observed"][data-data-link-action-outcome-result-event-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-action-outcome-target-event-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-action-outcome-target-run-id="dashboard-late-policy-run"]),
               "Late-data policy applied."
             )

      metadata =
        view
        |> render()
        |> element_attribute(
          "#dashboard-data-link-action-outcome",
          "data-data-link-action-outcome-metadata"
        )
        |> Jason.decode!()

      assert metadata == %{
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed",
               "dashboard_time_mode" => "live",
               "decision" => "accept",
               "execution_mode" => "sample_execution",
               "result_event_id" => policy_event.backfill_lifecycle_event_id,
               "target_event_id" => policy_event.backfill_lifecycle_event_id,
               "target_run_id" => "dashboard-late-policy-run"
             }

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               policy_event.backfill_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "late_data_accepted"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data execution mode"]),
               "sample_execution"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data source event type"]),
               "backfill_completed"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data selected samples"]),
               "1"
             )

      source_event_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="telemetry backfill lifecycle event"][data-data-link-related-id="#{source_event.backfill_lifecycle_event_id}"][data-data-link-related-kind="source_event"])

      assert has_element?(view, source_event_selector)

      view
      |> element(source_event_selector)
      |> render_click()

      source_event_path = assert_patch(view)
      assert source_event_path =~ "selected_target=telemetry_backfill_lifecycle_event"
      assert source_event_path =~ "selected_id=#{source_event.backfill_lifecycle_event_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Backfill lifecycle event"]),
               source_event.backfill_lifecycle_event_id
             )
    end

    test "records replay late-data policy decisions as audit-only events from the lifecycle inspector" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, source_event} =
               Cadence.record_telemetry_historical_data_workflow_event(
                 "backfill",
                 "completed",
                 %{
                   backfill_run_id: "dashboard-replay-late-policy-run",
                   organization_id: org.organization_id,
                   mission_id: mission.mission_id,
                   realm: :backfill,
                   data_source_id: "managed_questdb_replay",
                   binding_id: "replay_telemetry",
                   observable_id: "HK.counter",
                   point_id: "HK.counter",
                   source_from: ~U[2026-06-22 10:00:00Z],
                   source_to: ~U[2026-06-22 11:00:00Z],
                   receipt_from: ~U[2026-06-22 12:00:00Z],
                   receipt_to: ~U[2026-06-22 12:10:00Z],
                   sample_count: 3,
                   authority: :comparison,
                   reason: "operator_replay_backfill_completed",
                   actor_id: "system",
                   actor_kind: "system",
                   payload: %{"workflow" => "backfill", "stage" => "completed"}
                 },
                 dashboard_runtime_invalidation?: false
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=telemetry_backfill_lifecycle_event&selected_id=#{source_event.backfill_lifecycle_event_id}&time_mode=replay_run&replay_run_id=replay-late-policy-1&data_view=all_revisions&limit_mode=compare"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-controls[data-late-data-policy-source-event="#{source_event.backfill_lifecycle_event_id}"][data-late-data-policy-run-id="dashboard-replay-late-policy-run"][data-late-data-policy-execution-mode="event_only"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-dashboard-replay-run-id[value="replay-late-policy-1"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-dashboard-data-view[value="all_revisions"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-late-data-policy-dashboard-limit-mode[value="compare"])
             )

      view
      |> form("#dashboard-late-data-policy-form", %{
        "late_data_policy" => %{
          "decision" => "accept",
          "reason" => "operator_accepts_replay_late_data",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      result_path = assert_patch(view)

      events =
        Storage.list_backfill_lifecycle_events(
          mission.mission_id,
          organization_id: org.organization_id,
          backfill_run_id: "dashboard-replay-late-policy-run"
        )

      policy_event =
        Enum.find(events, &(&1.event_type == :late_data_accepted))

      assert policy_event.reason == "operator_accepts_replay_late_data"
      assert policy_event.sample_count == 3

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="late_data_policy"][data-data-link-action-outcome-status="ok"][data-data-link-action-outcome-reason="late_data_policy_applied"][data-data-link-action-outcome-decision="accept"][data-data-link-action-outcome-execution-mode="event_only"][data-data-link-action-outcome-dashboard-time-mode="replay_run"][data-data-link-action-outcome-dashboard-replay-run-id="replay-late-policy-1"][data-data-link-action-outcome-dashboard-data-view="all_revisions"][data-data-link-action-outcome-dashboard-limit-mode="compare"][data-data-link-action-outcome-result-event-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-action-outcome-target-event-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-action-outcome-target-run-id="dashboard-replay-late-policy-run"]),
               "Late-data policy applied."
             )

      metadata =
        view
        |> render()
        |> element_attribute(
          "#dashboard-data-link-action-outcome",
          "data-data-link-action-outcome-metadata"
        )
        |> Jason.decode!()

      assert metadata == %{
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-late-policy-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "compare",
               "decision" => "accept",
               "execution_mode" => "event_only",
               "result_event_id" => policy_event.backfill_lifecycle_event_id,
               "target_event_id" => policy_event.backfill_lifecycle_event_id,
               "target_run_id" => "dashboard-replay-late-policy-run"
             }

      result_event_id = URI.encode_www_form(policy_event.backfill_lifecycle_event_id)

      assert result_path =~ "selected_target=telemetry_backfill_lifecycle_event"
      assert result_path =~ "selected_id=#{result_event_id}"
      assert result_path =~ "time_mode=replay_run"
      assert result_path =~ "replay_run_id=replay-late-policy-1"
      assert result_path =~ "selected_data_view=all_revisions"
      assert result_path =~ "limit_mode=compare"
      assert result_path =~ "data_source_id=managed_questdb_replay"
      assert result_path =~ "source_binding_id=replay_telemetry"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_backfill_lifecycle_event"][data-data-link-target-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="replay-late-policy-1"][data-data-link-selected-data-source-id="managed_questdb_replay"][data-data-link-selected-source-binding-id="replay_telemetry"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data policy decision"]),
               "accept"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data execution mode"]),
               "event_only"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Sample count"]),
               "3"
             )

      copied_path =
        view
        |> render()
        |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

      assert copied_path =~ "selected_target=telemetry_backfill_lifecycle_event"
      assert copied_path =~ "selected_id=#{result_event_id}"
      assert copied_path =~ "time_mode=replay_run"
      assert copied_path =~ "replay_run_id=replay-late-policy-1"
      assert copied_path =~ "selected_data_view=all_revisions"
      assert copied_path =~ "limit_mode=compare"
      assert copied_path =~ "data_source_id=managed_questdb_replay"
      assert copied_path =~ "source_binding_id=replay_telemetry"

      stop_dashboard_view(view)

      {:ok, reopened_view, _html} = live(conn, copied_path)

      assert has_element?(
               reopened_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_backfill_lifecycle_event"][data-data-link-target-id="#{policy_event.backfill_lifecycle_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="replay-late-policy-1"][data-data-link-selected-data-source-id="managed_questdb_replay"][data-data-link-selected-source-binding-id="replay_telemetry"])
             )

      assert has_element?(
               reopened_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data policy decision"]),
               "accept"
             )

      assert has_element?(
               reopened_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Late data execution mode"]),
               "event_only"
             )

      stop_dashboard_view(reopened_view)
    end
  end
end
