defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceBindingWarningsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.PacketDefinition
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

  defp value_tile(point_id, mode, spacecraft_id) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts \\ []) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(42, 1, <<value::16>>)
      })

    with {:ok, result} <-
           Cadence.process_telemetry_ingress(
             evidence,
             binding_set.binding_set_id,
             binding_set.version
           ) do
      Cadence.Persistence.persist_processing_result(result, opts)
    end
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, packet_length::16,
      packet_data::binary>>
  end

  defp persist_dashboard_realm!(
         mission,
         realm,
         capabilities \\ %{range_scan?: true, latest?: true}
       ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "test-#{realm}-binding-#{System.unique_integer([:positive])}",
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
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

  describe "runtime source-binding warnings" do
    test "surfaces source-binding warnings on dashboard and widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Warning")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      _defaults = DataSources.ensure_default_managed_sources!()
      persist_dashboard_realm!(mission, :rehearsal)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Warnings",
          widgets: [value_tile("HK.counter", :fixed, spacecraft.spacecraft_id)]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      widget = render_item_by_title(document, "Counter").widget
      {:ok, view, _html} = live(conn, show_path(mission, dashboard) <> "?realm=rehearsal")
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-issues[data-dashboard-data-issue-codes*="missing_source_binding"])
             )

      refute has_element?(view, "#dashboard-source-health")

      assert has_element?(
               view,
               ~s(#widget-#{widget.widget_id} [data-warning-codes*="missing_source_binding"])
             )

      view
      |> element(
        ~s(#widget-#{widget.widget_id} [data-warning-evidence-open][phx-value-warning-code="missing_source_binding"][phx-value-logical-source="limits"][phx-value-realm="rehearsal"][phx-value-source-request-id])
      )
      |> render_click()

      warning_evidence_path = assert_patch(view)
      assert warning_evidence_path =~ "panel=evidence"
      assert warning_evidence_path =~ "selected_evidence_kind=warning"
      assert warning_evidence_path =~ "selected_warning_code=missing_source_binding"
      assert warning_evidence_path =~ "selected_logical_source=limits"
      assert warning_evidence_path =~ "selected_realm=rehearsal"
      assert warning_evidence_path =~ "selected_source_request="

      assert warning_evidence_path =~
               "selected_placement=#{URI.encode_www_form(widget.widget_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="warning"][data-evidence-subject="missing_source_binding"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="warning"][data-dashboard-evidence-logical-source="limits"][data-dashboard-evidence-realm="rehearsal"][data-dashboard-selection-state="none"])
             )

      view
      |> element(
        ~s(#dashboard-evidence-inspector [data-evidence-link-target="telemetry point"][data-evidence-link-id="HK.counter"])
      )
      |> render_click()

      data_link_path = assert_patch(view)
      assert data_link_path =~ "panel=data_link"
      assert data_link_path =~ "selected_target=telemetry_point"
      assert data_link_path =~ "realm=rehearsal"
      refute data_link_path =~ "selected_evidence_kind="

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_point"][data-data-link-status="context_only"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )

      refute has_element?(view, "#dashboard-source-health")

      missing_warning_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "evidence", selected_evidence_kind: "warning", selected_placement: widget.widget_id, selected_warning_code: "missing_warning", selected_source_request: "stale-source-request", selected_logical_source: "limits", selected_realm: "rehearsal"}}"

      {:ok, missing_warning_view, _html} = live(conn, missing_warning_path)
      render_dashboard_async(missing_warning_view)

      assert has_element?(
               missing_warning_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="warning"][data-evidence-status="missing"][data-evidence-subject="missing_warning"])
             )

      assert has_element?(
               missing_warning_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="missing"][data-dashboard-evidence-kind="warning"][data-dashboard-evidence-logical-source="limits"][data-dashboard-evidence-realm="rehearsal"])
             )

      missing_source_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "evidence", selected_evidence_kind: "source", selected_logical_source: "telemetry", selected_realm: "missing-realm", selected_data_source: "missing-source", selected_source_binding: "missing-binding"}}"

      {:ok, missing_source_view, _html} = live(conn, missing_source_path)
      render_dashboard_async(missing_source_view)

      assert has_element?(
               missing_source_view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="missing"][data-evidence-subject="telemetry"])
             )

      assert has_element?(
               missing_source_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="missing"][data-dashboard-evidence-kind="source"][data-dashboard-evidence-logical-source="telemetry"][data-dashboard-evidence-realm="missing-realm"][data-dashboard-evidence-data-source-id="missing-source"][data-dashboard-evidence-source-binding-id="missing-binding"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()
      cleared_source_evidence_path = assert_patch(view)
      assert cleared_source_evidence_path =~ "realm=rehearsal"
      refute cleared_source_evidence_path =~ "panel="
      refute cleared_source_evidence_path =~ "selected_evidence_kind="
    end
  end
end
