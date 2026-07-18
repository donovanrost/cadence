defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetEventMarkerNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

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

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
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
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

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
    test "opens contact and mission event chart markers with navigation context" do
      disable_telemetry_storage_runtime_invalidation!()

      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
      binding_set = persist_binding_set!(org, mission)
      scheduled_contact = persist_scheduled_contact!(org, mission)
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

      contact_marker =
        Enum.find(
          event_markers,
          &(&1["marker_type"] == "contact_interval" and
              &1["contact_id"] == scheduled_contact.scheduled_contact_id)
        )

      mission_event_marker =
        Enum.find(
          event_markers,
          &(&1["marker_type"] == "mission_event" and
              &1["source_record_id"] == persisted_event.event_id)
        )

      contact_link_id = contact_marker["link_id"]
      contact_target_id = contact_marker["target_id"]
      contact_timestamp_ms = contact_marker["starts_at_ms"]

      chart_id = chart_dom_id(render(view), trend_widget_id)

      view
      |> element("##{chart_id}")
      |> render_hook("open_data_link", %{
        "link-id" => contact_link_id,
        "placement-id" => trend_widget_id,
        "target" => "contact",
        "target-id" => scheduled_contact.scheduled_contact_id,
        "timestamp-ms" => contact_timestamp_ms
      })

      assert_push_event(
        view,
        "tlm:select",
        %{
          "selection" => %{
            "link_id" => ^contact_link_id,
            "placement_id" => ^trend_widget_id,
            "target" => "contact",
            "target_id" => ^contact_target_id,
            "timestamp_ms" => ^contact_timestamp_ms
          }
        },
        1_000
      )

      contact_path = assert_patch(view)
      assert contact_path =~ "panel=data_link"
      assert contact_path =~ "selected_target=contact"

      assert contact_path =~
               "selected_id=#{URI.encode_www_form(scheduled_contact.scheduled_contact_id)}"

      assert contact_path =~ "selected_placement=#{URI.encode_www_form(trend_widget_id)}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )

      view |> element(~s(#dashboard-panel button[aria-label="Close panel"])) |> render_click()

      closed_path = assert_patch(view)
      refute closed_path =~ "panel=data_link"
      refute has_element?(view, "#dashboard-panel")

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
  end
end
