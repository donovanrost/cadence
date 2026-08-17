defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetEventMarkerNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Projections.MissionEvents
  alias Cadence.Repo
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
        packet_definition_id: "hk-event-marker",
        packet_name: "HK",
        apid: 47,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-event-marker-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-event-marker-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-event-marker-rule",
            capability_instance_id: mission.mission_id <> "-event-marker-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 47,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp ingest!(mission, binding_set, spacecraft_id, value, unix_seconds) do
    evidence =
      RawEvidence.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft_id,
        receipt_time: DateTime.from_unix!(unix_seconds, :second),
        raw: build_space_packet(47, 1, <<value::16>>)
      })

    {:ok, _result} =
      Cadence.process_and_persist_telemetry_ingress(
        evidence,
        binding_set.binding_set_id,
        binding_set.version
      )
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

  defp persist_scheduled_contact!(org, mission) do
    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "dashboard-contact-alpha",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: DateTime.from_unix!(1_700_000_080, :second),
        ends_at: DateTime.from_unix!(1_700_000_220, :second)
      })

    assert {:ok, persisted} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, scheduled_contact)

    persisted
  end

  defp persist_mission_event!(org, mission, binding_set, spacecraft) do
    event_time = DateTime.from_unix!(1_700_000_120, :second)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:event-marker",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        occurred_at: event_time,
        recorded_at: event_time,
        effective_at: event_time,
        category: :runtime,
        kind: :binding_set_activated,
        severity: :info,
        actor: %{kind: :system, id: "dashboard-event-marker-test"},
        subject: %{kind: :binding_set, id: binding_set.binding_set_id},
        scope: %{
          spacecraft_id: spacecraft.spacecraft_id,
          source_endpoint_ref: "source-endpoint-alpha"
        },
        causality: %{
          correlation_id: binding_set.binding_set_id,
          source_record_kind: :binding_set_activation,
          source_record_id: "dashboard-event-marker-activation"
        },
        payload: %{
          binding_set_id: binding_set.binding_set_id,
          binding_set_version: binding_set.version,
          activation_id: "dashboard-event-marker-activation"
        },
        current: %{state: :active},
        metadata: %{"source" => "dashboard-event-marker-test"}
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    assert {:ok, 1} =
             MissionEvents.persist_entries(Repo, MissionEvents.project_many([persisted_event]))

    persisted_event
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

  defp chart_event_markers(html, widget_id) do
    chart_attribute(html, widget_id, "data-event-markers")
  end

  defp chart_attribute(html, widget_id, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute(attribute)

    Jason.decode!(value)
  end

  defp chart_dom_id(html, widget_id) do
    [id] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
      |> LazyHTML.attribute("id")

    id
  end

  defp disable_telemetry_storage_runtime_invalidation! do
    previous_config = Application.get_env(:cadence, :telemetry_storage, [])

    Application.put_env(
      :cadence,
      :telemetry_storage,
      Keyword.put(previous_config, :dashboard_runtime_invalidation?, false)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_config)
    end)
  end

  describe "live widget event marker navigation" do
    test "opens mission event chart markers with navigation context" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)
      persisted_event = persist_mission_event!(org, mission, binding_set, spacecraft)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
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
      trend_widget_id = render_item_by_title(document, "Counter Trend").widget.widget_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      html = render_dashboard_async(view)

      event_markers = chart_event_markers(html, trend_widget_id)

      mission_event_marker =
        Enum.find(
          event_markers,
          &(&1["marker_type"] == "mission_event" and
              &1["source_record_id"] == persisted_event.event_id)
        )

      mission_event_link_id = mission_event_marker["link_id"]
      mission_event_id = mission_event_marker["mission_event_id"]
      mission_event_timestamp_ms = mission_event_marker["timestamp_ms"]
      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => mission_event_link_id,
        "placement-id" => trend_widget_id,
        "target" => "mission_event",
        "target-id" => mission_event_id,
        "timestamp-ms" => mission_event_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^mission_event_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "mission_event",
            "target_id" => ^mission_event_id,
            "timestamp_ms" => ^mission_event_timestamp_ms
          }
        },
        1_000
      )

      mission_event_path = assert_patch(view)
      assert mission_event_path =~ "panel=data_link"
      assert mission_event_path =~ "selected_target=mission_event"
      assert mission_event_path =~ "selected_id=#{URI.encode_www_form(mission_event_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="mission_event"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{persisted_event.event_id}"][data-data-link-related-kind="source_event"])
             )

      view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{persisted_event.event_id}"])
      )
      |> render_click()

      operational_event_path = assert_patch(view)
      assert operational_event_path =~ "panel=data_link"
      assert operational_event_path =~ "selected_target=operational_event"

      assert operational_event_path =~
               "selected_id=#{URI.encode_www_form(persisted_event.event_id)}"

      assert operational_event_path =~ "nav_from_target=mission_event"

      assert operational_event_path =~
               "nav_from_target_id=#{URI.encode_www_form(mission_event_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-status="resolved"])
             )
    end

    test "standard dashboards omit contacts while marker toggles filter annotations" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Marker Toggle")
      binding_set = persist_binding_set!(org, mission)
      _scheduled_contact = persist_scheduled_contact!(org, mission)
      _persisted_event = persist_mission_event!(org, mission, binding_set, spacecraft)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Marker Toggles",
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
      trend_widget_id = render_item_by_title(document, "Counter Trend").widget.widget_id

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      html = render_dashboard_async(view)

      marker_types =
        html |> chart_event_markers(trend_widget_id) |> Enum.map(& &1["marker_type"])

      refute "contact_interval" in marker_types
      assert "mission_event" in marker_types

      chart_id_before = chart_dom_id(html, trend_widget_id)
      refute has_element?(view, "#dashboard-marker-contacts")

      view
      |> form("#runtime-context-form", %{"markers" => %{"mission_events" => "false"}})
      |> render_change()

      toggled_path = assert_patch(view)
      assert toggled_path =~ "hidden_markers=mission_events"

      html = render_dashboard_async(view)

      filtered_types =
        html |> chart_event_markers(trend_widget_id) |> Enum.map(& &1["marker_type"])

      refute "contact_interval" in filtered_types
      refute "mission_event" in filtered_types

      # Presentation-only change: chart remounted (new epoch id)...
      assert chart_dom_id(html, trend_widget_id) != chart_id_before
      # ...and the checkbox now renders unchecked with the hidden-count hint.
      refute has_element?(view, ~s(#dashboard-marker-mission_events[checked]))
      assert has_element?(view, "#dashboard-markers-hidden-count")

      view
      |> form("#runtime-context-form", %{"markers" => %{"mission_events" => "true"}})
      |> render_change()

      restored_path = assert_patch(view)
      refute restored_path =~ "hidden_markers"

      html = render_dashboard_async(view)

      restored_types =
        html |> chart_event_markers(trend_widget_id) |> Enum.map(& &1["marker_type"])

      assert "mission_event" in restored_types
      refute "contact_interval" in restored_types
    end

    test "widget inspect panel opens from the details popover with table and CSV" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Inspect")
      binding_set = persist_binding_set!(org, mission)

      ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
      ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Inspect",
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

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("[data-widget-inspect-data]") |> render_click()

      assert has_element?(
               view,
               ~s(#dashboard-widget-inspector[data-widget-inspect-state="ready"])
             )

      html = render(view)
      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("#dashboard-panel h2") |> LazyHTML.text() =~
               "Inspect: Counter Trend"

      table = document |> LazyHTML.query("[data-widget-inspect-table]") |> LazyHTML.text()
      assert table =~ "14"
      assert table =~ "15"

      assert [csv] =
               document
               |> LazyHTML.query("#dashboard-widget-inspect-download")
               |> LazyHTML.attribute("data-csv")

      assert csv =~ "time_utc"
      assert csv =~ "14"

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()
      refute has_element?(view, "#dashboard-widget-inspector")
    end
  end
end
