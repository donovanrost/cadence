defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceCapabilityWarningsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

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

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
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

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
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
      RuntimePersistence.persist_processing_result(result, opts)
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
         capabilities
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

  describe "runtime unsupported source capability warnings" do
    test "surfaces unsupported source capability warnings on widgets" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Capability")
      binding_set = persist_binding_set!(org, mission)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 5, 1_700_000_100)
      _defaults = DataSources.ensure_default_managed_sources!()
      persist_dashboard_realm!(mission, :flight, %{latest?: true, range_scan?: false})

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Capability",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      widget = render_item_by_title(document, "Counter Trend").widget
      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-issues[data-dashboard-data-issue-codes*="unsupported_source_capability"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-refresh-status="degraded"][data-runtime-refresh-reason="source_execution_degraded"][data-runtime-visible-refresh-action="accept_result"][data-runtime-source-execution-degraded="1"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-source-execution-degraded-identities*="telemetry"][data-runtime-source-execution-degraded-identities*="unsupported_capability"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-runtime-source-execution-degraded-actions*="requires_configuration_change"][data-runtime-source-execution-degraded-actions*="inspect_source_capability"])
             )

      view
      |> element("#dashboard-diagnostics-button")
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel[data-runtime-source-execution-degraded-identities*="telemetry"][data-runtime-source-execution-degraded-actions*="requires_configuration_change"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-execution-degraded-summary[data-source-execution-degraded-count="1"][data-source-execution-degraded-identity*="telemetry"][data-source-execution-degraded-identity*="unsupported_capability"][data-source-execution-degraded-status="unsupported_capability"][data-source-execution-runtime-action="requires_configuration_change"][data-source-execution-operator-action="inspect_source_capability"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-execution-degraded-summary [data-source-execution-field="Runtime"]),
               "requires_configuration_change"
             )

      assert has_element?(
               view,
               ~s(#dashboard-source-execution-degraded-summary [data-source-execution-field="Operator"]),
               "inspect_source_capability"
             )

      assert has_element?(
               view,
               ~s(#dashboard-diagnostics-panel [data-diagnostics-field="Degraded source identities"]),
               "telemetry"
             )

      assert has_element?(
               view,
               ~s(#dashboard-degraded-source-drilldowns [data-degraded-source-logical-source="telemetry"][data-degraded-source-status="unsupported_capability"][data-degraded-source-runtime-action="requires_configuration_change"])
             )

      view
      |> element(
        ~s(#dashboard-degraded-source-drilldowns [data-degraded-source-logical-source="telemetry"])
      )
      |> render_click()

      degraded_source_evidence_path = assert_patch(view)
      assert degraded_source_evidence_path =~ "panel=evidence"
      assert degraded_source_evidence_path =~ "selected_evidence_kind=source"
      assert degraded_source_evidence_path =~ "selected_source_evidence_mode=execution"
      assert degraded_source_evidence_path =~ "selected_logical_source=telemetry"
      assert degraded_source_evidence_path =~ "selected_source_request="

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="active"][data-dashboard-evidence-kind="source"][data-dashboard-evidence-source-request])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Source request"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Execution status"]),
               "unsupported_capability"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Execution runtime action"]),
               "requires_configuration_change"
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()
      refute assert_patch(view) =~ "panel="

      assert has_element?(
               view,
               ~s(#widget-#{widget.widget_id} [data-warning-codes*="unsupported_source_capability"])
             )

      assert has_element?(
               view,
               ~s([data-engine-warning="unsupported_source_capability"]),
               "Unsupported source capability"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-detail="Requested sampling"]),
               "raw_series"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-detail="Supported sampling 1"]),
               "latest"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-detail="Source execution action"]),
               "inspect_source_capability"
             )

      assert has_element?(
               view,
               ~s([data-engine-warning-detail="unsupported_source_capability"] [data-warning-link-target="telemetry point"][data-warning-link-id="HK.counter"][phx-value-data-source-id][phx-value-source-binding-id])
             )

      view
      |> element(
        ~s(#widget-#{widget.widget_id} [data-engine-warning-detail="unsupported_source_capability"] [data-warning-link-target="telemetry point"][data-warning-link-id="HK.counter"][phx-value-data-source-id][phx-value-source-binding-id])
      )
      |> render_click()

      unsupported_link_path = assert_patch(view)
      assert unsupported_link_path =~ "panel=data_link"
      assert unsupported_link_path =~ "selected_target=telemetry_point"
      assert unsupported_link_path =~ "data_source_id="
      assert unsupported_link_path =~ "source_binding_id="

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_point"][data-data-link-status="context_only"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
               "HK.counter"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Source request"])
             )
    end
  end
end
