defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceCapabilityWarningsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Management.DataSources
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

      data_health = dashboard_toolbar_data_health(view)

      assert data_health["root"]["attrs"]["id"] == "dashboard-data-issues"

      assert data_health["root"]["attrs"]["data-dashboard-data-issue-codes"] =~
               "unsupported_source_capability"

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

      diagnostics_attrs =
        dashboard_toolbar_menu_item(view, "dashboard-diagnostics-button")["link"]["attrs"]

      assert diagnostics_attrs["href"] =~ "/diagnostics"
      assert diagnostics_attrs["data-phx-link"] == "redirect"
      assert diagnostics_attrs["data-phx-link-state"] == "push"

      header = widget_header_presentation(view, widget.widget_id)
      assert header["root"]["attrs"]["data-warning-codes"] =~ "unsupported_source_capability"

      widget_warnings =
        view
        |> widget_warning_presentations(widget.widget_id)
        |> Enum.filter(fn warning ->
          warning["overlay"]["attrs"]["data-engine-warning-detail"] ==
            "unsupported_source_capability"
        end)

      assert widget_warnings != []

      Enum.each(widget_warnings, fn warning ->
        assert String.starts_with?(
                 warning["component_id"],
                 "widget-#{widget.widget_id}-engine-warning-"
               )

        assert String.ends_with?(warning["component_id"], "-component")
      end)

      presentations =
        (widget_warnings ++ standalone_warning_presentations(view))
        |> Enum.filter(fn warning ->
          warning["overlay"]["attrs"]["data-engine-warning-detail"] ==
            "unsupported_source_capability"
        end)

      assert Enum.any?(
               presentations,
               &(&1["trigger"]["badge"]["attrs"]["data-engine-warning"] ==
                   "unsupported_source_capability")
             )

      assert Enum.any?(
               presentations,
               &(&1["trigger"]["badge"]["text"] == "Unsupported source capability")
             )

      details = Enum.flat_map(presentations, & &1["body"]["details"]["rows"])

      assert detail_text(details, "Requested sampling") == "raw_series"
      assert detail_text(details, "Supported sampling 1") == "latest"

      assert detail_text(details, "Source execution action") ==
               "inspect_source_capability"

      unsupported_link =
        presentations
        |> Enum.flat_map(& &1["body"]["links"]["rows"])
        |> Enum.find(fn link ->
          link["attrs"]["data-warning-link-target"] == "telemetry point" and
            link["attrs"]["data-warning-link-id"] == "HK.counter"
        end)

      assert unsupported_link
      assert Map.has_key?(unsupported_link["attrs"], "phx-value-data-source-id")
      assert Map.has_key?(unsupported_link["attrs"], "phx-value-source-binding-id")

      render_hook(
        view,
        unsupported_link["attrs"]["phx-click"],
        event_params(unsupported_link["attrs"])
      )

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

      stop_dashboard_view(view)
    end
  end

  defp detail_text(details, label) do
    case Enum.find(details, &(&1["value"]["attrs"]["data-warning-detail"] == label)) do
      nil -> nil
      detail -> detail["value"]["text"]
    end
  end

  defp event_params(attrs) do
    attrs
    |> Enum.flat_map(fn
      {"phx-value-" <> name, value} -> [{name, value}]
      {_name, _value} -> []
    end)
    |> Map.new()
  end

  defp standalone_warning_presentations(view) do
    html = render(view)

    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([id^="widget-"][id*="-engine-warning-"][id$="-component"]))
    |> LazyHTML.attribute("id")
    |> Enum.map(fn id ->
      html
      |> LiveVue.Test.get_vue(id: id)
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")
    end)
  end
end
