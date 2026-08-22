defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContactScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Runtime.Persistence, as: RuntimePersistence

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.Dashboards.{Document, RenderItem}
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

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds, opts) do
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

  defp contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "dashboard-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "dashboard-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
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

  describe "runtime contact scope diagnostics" do
    test "contact-scoped telemetry no-data exposes scope filter diagnostics" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      scheduled_contact =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-runtime-empty-contact",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.Contacts.persist_scheduled_contact(org.organization_id, scheduled_contact)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
        source_endpoint_id: "source-endpoint-beta"
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Scoped Empty Power",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 0, y: 0, w: 6, h: 3}
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_item = render_item_by_title(document, "Counter Trend")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: scheduled_contact.scheduled_contact_id}}"
        )

      render_dashboard_async(view)

      widget_selector = "#widget-#{trend_item.placement_id}"

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-data-state="no_data"][data-widget-source-empty-reason="contact_scope_no_data"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-scope-kinds="spacecraft"][data-widget-source-contact-ids="dashboard-runtime-empty-contact"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-source-endpoint-ids="source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-health-state="stale"][data-dashboard-health-stale-placements="#{trend_item.placement_id}"][data-dashboard-health-affected-placements="#{trend_item.placement_id}"])
             )

      assert has_element?(view, "#dashboard-data-issues")
      refute has_element?(view, "#dashboard-health-rollup")
      refute has_element?(view, ~s([data-ops-context-section="dashboard_health"]))
      refute has_element?(view, ~s([data-ops-context-section="source_status"]))
      refute has_element?(view, ~s([data-ops-context-section="source_selection"]))

      assert has_element?(
               view,
               ~s(#{widget_selector} button[data-widget-source-badge="unknown"][data-widget-source-badge-inventory-action="source_inventory"][data-widget-source-badge-inventory-href*="/ops/data-sources"][data-widget-source-badge-inventory-href*="contact_id=dashboard-runtime-empty-contact"][data-widget-source-badge-inventory-href*="source_endpoint_id=source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} a[data-widget-source-badge-inventory-open="unknown"][href*="/ops/data-sources"][href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} [data-widget-query-diagnostics][data-widget-query-source-state="unknown"][data-widget-query-data-view="canonical"][data-widget-query-time-modes="live"][data-widget-query-contact-ids="dashboard-runtime-empty-contact"][data-widget-query-source-endpoint-ids="source-endpoint-alpha"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} [data-widget-query-value="contacts"]),
               "dashboard-runtime-empty-contact"
             )

      view
      |> element(~s(#{widget_selector} [data-widget-query-evidence-open]))
      |> render_click()

      query_evidence_path = assert_patch(view)
      assert query_evidence_path =~ "panel=evidence"
      assert query_evidence_path =~ "selected_evidence_kind=query"
      assert query_evidence_path =~ "selected_widget_title=Counter+Trend"
      assert query_evidence_path =~ "selected_requested_data_view=canonical"
      assert query_evidence_path =~ "selected_source_evidence_state=unknown"
      assert query_evidence_path =~ "selected_contact_id=dashboard-runtime-empty-contact"
      assert query_evidence_path =~ "selected_source_endpoint_id=source-endpoint-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="query"][data-evidence-status="unknown"][data-evidence-subject="Counter Trend"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-subject-field="Widget"]),
               "Counter Trend"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Contact"]),
               "dashboard-runtime-empty-contact"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=query"][data-clipboard-text*="selected_widget_title=Counter+Trend"][data-clipboard-text*="selected_contact_id=dashboard-runtime-empty-contact"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-inventory[href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      view
      |> element(~s(#{widget_selector} button[data-widget-source-badge="unknown"]))
      |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="source"][data-evidence-status="unknown"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Contact"]),
               "dashboard-runtime-empty-contact"
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Source endpoint"]),
               "source-endpoint-alpha"
             )

      assert render(view) =~
               "Widget source status is unknown; source health or watermark evidence could not prove freshness for this value."

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-health[href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-source-inventory[href*="contact_id=dashboard-runtime-empty-contact"][href*="source_endpoint_id=source-endpoint-alpha"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
             )

      stop_dashboard_view(view)
    end

    test "multi-contact telemetry no-data preserves every contact in diagnostics and evidence" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)

      contact_alpha =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-runtime-empty-contact-alpha",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-alpha"],
          paths: contact_paths("source-endpoint-alpha"),
          starts_at: DateTime.from_unix!(1_700_000_080, :second),
          ends_at: DateTime.from_unix!(1_700_000_220, :second)
        })

      contact_gamma =
        ScheduledContact.new(%{
          scheduled_contact_id: "dashboard-runtime-empty-contact-gamma",
          mission_id: mission.mission_id,
          source_endpoint_refs: ["source-endpoint-gamma"],
          paths: contact_paths("source-endpoint-gamma"),
          starts_at: DateTime.from_unix!(1_700_000_240, :second),
          ends_at: DateTime.from_unix!(1_700_000_360, :second)
        })

      assert {:ok, _scheduled_contact} =
               Cadence.Contacts.persist_scheduled_contact(org.organization_id, contact_alpha)

      assert {:ok, _scheduled_contact} =
               Cadence.Contacts.persist_scheduled_contact(org.organization_id, contact_gamma)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
        source_endpoint_id: "source-endpoint-beta"
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Multi-Contact Empty Power",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 0, y: 0, w: 6, h: 3}
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_item = render_item_by_title(document, "Counter Trend")
      scope_ids = "#{contact_alpha.scheduled_contact_id},#{contact_gamma.scheduled_contact_id}"

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_ids: scope_ids}}"
        )

      render_dashboard_async(view)

      widget_selector = "#widget-#{trend_item.placement_id}"

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="contact"][data-dashboard-scope-id="#{contact_alpha.scheduled_contact_id}"][data-dashboard-scope-ids="#{scope_ids}"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-data-state="no_data"][data-widget-source-empty-reason="contact_scope_no_data"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector}[data-widget-source-contact-ids="#{scope_ids}"][data-widget-source-source-endpoint-ids="source-endpoint-alpha,source-endpoint-gamma"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} [data-widget-query-diagnostics][data-widget-query-source-state="unknown"][data-widget-query-contact-ids="#{scope_ids}"][data-widget-query-source-endpoint-ids="source-endpoint-alpha,source-endpoint-gamma"])
             )

      assert has_element?(
               view,
               ~s(#{widget_selector} button[data-widget-source-badge="unknown"][phx-value-contact-id="#{contact_alpha.scheduled_contact_id}"][phx-value-contact-ids="#{scope_ids}"][phx-value-source-endpoint-id="source-endpoint-alpha"])
             )

      view
      |> element(~s(#{widget_selector} [data-widget-query-evidence-open]))
      |> render_click()

      query_evidence_path = assert_patch(view)
      decoded_query_evidence_path = URI.decode(query_evidence_path)

      assert decoded_query_evidence_path =~ "panel=evidence"
      assert decoded_query_evidence_path =~ "selected_evidence_kind=query"

      assert decoded_query_evidence_path =~
               "selected_contact_id=#{contact_alpha.scheduled_contact_id}"

      assert decoded_query_evidence_path =~ "selected_contact_ids=#{scope_ids}"
      assert decoded_query_evidence_path =~ "selected_source_endpoint_id=source-endpoint-alpha"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Contacts"]),
               scope_ids
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-detail="Contact"]),
               contact_alpha.scheduled_contact_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="selected_contact_ids=#{URI.encode_www_form(scope_ids)}"])
             )

      stop_dashboard_view(view)
    end
  end
end
