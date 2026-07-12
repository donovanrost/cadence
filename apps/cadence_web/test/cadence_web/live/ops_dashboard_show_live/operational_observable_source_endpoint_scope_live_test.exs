defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance
  }

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{Path, RealizedContact}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    OperationalEventRow
  }

  alias Cadence.Repo
  alias Cadence.Runtime.TransportActionRequest
  alias Cadence.SourceEndpoints.SourceEndpoint
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

  defp enable_dashboard_engine_inline_resolves! do
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end

  defp persist_command_queue_entry!(
         org,
         mission,
         command_queue_entry_id,
         source_endpoint_ref,
         lifecycle_state \\ :pending
       ) do
    requested_at = ~U[2026-06-17 12:00:00Z]
    command_request_id = "#{command_queue_entry_id}-request"

    command_request =
      CommandRequest.new(%{
        command_request_id: command_request_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_ref,
        command_snapshot_id: "#{command_queue_entry_id}-snapshot",
        command_id: "#{command_queue_entry_id}-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 3,
        requested_by: %{"user_id" => "dashboard-test"},
        requested_at: requested_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: command_queue_entry_id,
        mission_id: mission.mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: source_endpoint_ref,
        queue_lane_key: source_endpoint_ref,
        priority: 3,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: lifecycle_state,
        enqueued_by: %{"user_id" => "dashboard-test"},
        enqueued_at: requested_at,
        metadata: %{}
      })

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    command_queue_entry
  end

  defp persist_command_release_attempt!(org, mission, queue_entry) do
    attempted_at = ~U[2026-06-17 12:00:30Z]

    release_attempt =
      CommandReleaseAttempt.new(%{
        command_release_attempt_id: "#{queue_entry.command_queue_entry_id}-release",
        mission_id: mission.mission_id,
        command_queue_entry_id: queue_entry.command_queue_entry_id,
        command_request_id: queue_entry.command_request_id,
        source_endpoint_ref: queue_entry.source_endpoint_ref,
        realized_contact_id: "dashboard-contact-alpha",
        path_id: "dashboard-uplink-path",
        transport_binding_id: "dashboard-transport-binding",
        command_snapshot_id: "#{queue_entry.command_queue_entry_id}-snapshot",
        command_id: "#{queue_entry.command_queue_entry_id}-command",
        command_name: "NOOP",
        layout_kind: :ccsds_space_packet,
        preferred_uplink_service: "tc",
        apid: 42,
        service_type: 17,
        service_subtype: 1,
        opcode: %{kind: "noop"},
        encoded_binary_base64: Base.encode64("NOOP"),
        encoded_size_bytes: 4,
        lifecycle_state: :released,
        verification_state: :pending,
        released_by: %{"user_id" => "dashboard-test"},
        attempted_at: attempted_at,
        released_at: attempted_at,
        metadata: %{
          "transport_action_request_id" =>
            "#{queue_entry.command_queue_entry_id}-transport-action"
        }
      })

    assert %CommandReleaseAttemptRow{} =
             Repo.insert!(
               CommandReleaseAttemptRow.changeset(%CommandReleaseAttempt{
                 release_attempt
                 | organization_id: org.organization_id
               })
             )

    release_attempt
  end

  defp persist_transport_action_event_for_release_attempt!(org, mission, release_attempt) do
    action_request_id = transport_action_request_id!(release_attempt)
    requested_at = DateTime.add(release_attempt.attempted_at, 1, :second)

    action_request = %TransportActionRequest{
      action_request_id: action_request_id,
      mission_id: mission.mission_id,
      realized_contact_id: release_attempt.realized_contact_id,
      path_id: release_attempt.path_id,
      capability_instance_id: "live-uplink-gateway-alpha",
      family_key: :uplink_gateway,
      activation_id: "live-transport-activation-alpha",
      binding_set_id: release_attempt.transport_binding_id,
      binding_set_version: 1,
      partition_affinity: :source_endpoint,
      partition_value: release_attempt.source_endpoint_ref,
      command_release_attempt_id: release_attempt.command_release_attempt_id,
      command_request_id: release_attempt.command_request_id,
      source_endpoint_ref: release_attempt.source_endpoint_ref,
      command_name: release_attempt.command_name,
      signal_phase: :start,
      action_kind: :release_command,
      request_document: %{
        "command_request_id" => release_attempt.command_request_id,
        "command_release_attempt_id" => release_attempt.command_release_attempt_id,
        "encoded_size_bytes" => release_attempt.encoded_size_bytes,
        "preferred_uplink_service" => release_attempt.preferred_uplink_service
      },
      requested_at: requested_at,
      metadata: %{"command_release_attempt_id" => release_attempt.command_release_attempt_id}
    }

    event =
      action_request
      |> Event.from_transport_action_request()
      |> then(fn %Event{} = event -> %Event{event | organization_id: org.organization_id} end)

    assert %OperationalEventRow{} =
             Repo.insert!(OperationalEventRow.changeset(event))

    event
  end

  defp transport_action_request_id!(release_attempt) do
    release_attempt.metadata["transport_action_request_id"] ||
      release_attempt.metadata[:transport_action_request_id]
  end

  defp persist_realized_contact_for_release_attempt!(org, mission, release_attempt) do
    realized_at = DateTime.add(release_attempt.attempted_at, -60, :second)

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: release_attempt.realized_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [release_attempt.source_endpoint_ref],
        contact_intents: [:command_window],
        paths: [
          Path.new(%{
            path_id: release_attempt.path_id,
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: release_attempt.source_endpoint_ref
          })
        ],
        clock_mode: :live,
        lifecycle_state: :active,
        initial_time: realized_at,
        realized_at: realized_at,
        metadata: %{"command_release_attempt_id" => release_attempt.command_release_attempt_id}
      })

    assert {:ok, %RealizedContact{} = persisted_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    persisted_contact
  end

  defp persist_command_verifier_instance_for_release_attempt!(org, mission, release_attempt) do
    matched_at = DateTime.add(release_attempt.attempted_at, 5, :second)

    verifier_instance =
      CommandVerifierInstance.new(%{
        command_verifier_instance_id:
          "#{release_attempt.command_release_attempt_id}-verifier-instance",
        mission_id: mission.mission_id,
        command_request_id: release_attempt.command_request_id,
        command_release_attempt_id: release_attempt.command_release_attempt_id,
        source_endpoint_ref: release_attempt.source_endpoint_ref,
        command_snapshot_id: release_attempt.command_snapshot_id,
        command_id: release_attempt.command_id,
        command_name: release_attempt.command_name,
        verifier_id: "live-transport-verifier",
        verifier_name: "Live transport verifier",
        phase: :start,
        severity: :info,
        lifecycle_state: :satisfied,
        matched_record_kind: :transport_action_request,
        matched_record_id: transport_action_request_id!(release_attempt),
        matched_at: matched_at,
        metadata: %{"command_release_attempt_id" => release_attempt.command_release_attempt_id}
      })

    assert %CommandVerifierInstanceRow{} =
             Repo.insert!(
               CommandVerifierInstanceRow.changeset(%CommandVerifierInstance{
                 verifier_instance
                 | organization_id: org.organization_id
               })
             )

    %CommandVerifierInstance{verifier_instance | organization_id: org.organization_id}
  end

  describe "source endpoint operational observable scope rendering" do
    test "filters operational observable transport rows and preserves DataLink context" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => "dss-63"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

      alpha_transport =
        Transport.new(%{
          transport_id: "dashboard-transport-alpha",
          mission_id: mission.mission_id,
          display_name: "Alpha TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "alpha.ground.example",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14"
          }
        })

      beta_transport =
        Transport.new(%{
          transport_id: "dashboard-transport-beta",
          mission_id: mission.mission_id,
          display_name: "Beta TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "beta.ground.example",
            "port" => "5001",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{
            "source_endpoint_id" => beta_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-63"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Source Endpoint Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=source_endpoint&scope_id=#{alpha_endpoint.source_endpoint_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{alpha_endpoint.source_endpoint_id}"])
             )

      alpha_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"][data-status-matrix-supported-capability="connection_state"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"][data-status-matrix-row-link-id="dashboard-transport-alpha"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(view, beta_row_selector)

      view
      |> element(
        alpha_row_selector <>
          ~s( [data-status-matrix-row-link="comms.transport.connection_state:dashboard-transport-alpha"][data-status-matrix-row-link-target="transport"])
      )
      |> render_click()

      transport_link_path = assert_patch(view)
      assert transport_link_path =~ "panel=data_link"
      assert transport_link_path =~ "selected_target=transport"
      assert transport_link_path =~ "selected_id=dashboard-transport-alpha"
      assert transport_link_path =~ "scope_kind=source_endpoint"
      assert transport_link_path =~ "scope_id=#{alpha_endpoint.source_endpoint_id}"
      assert transport_link_path =~ "realm=flight"
      assert transport_link_path =~ "data_source_id=managed_operational_observables"
      assert transport_link_path =~ "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=dashboard-source-endpoint-alpha"][data-clipboard-text*="selected_target=transport"][data-clipboard-text*="selected_id=dashboard-transport-alpha"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
             )

      stop_dashboard_view(view)
    end

    test "opens live source-endpoint ingress-latency operational-event copied route from frame evidence" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "ingress-latency-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Ingress latency endpoint",
          metadata: %{"spacecraft_id" => "spacecraft-alpha"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      observed_at =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      metric_event =
        %{
          sample_id: "ingress-latency-live-rendered-alpha",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          observable_id: "ingress.processing_latency_ms",
          resource_id: source_endpoint.source_endpoint_id,
          scope_kind: :source_endpoint,
          source_endpoint_id: source_endpoint.source_endpoint_id,
          spacecraft_id: "spacecraft-alpha",
          value: 4.5,
          processing_latency_ms: 4.5,
          unit: "ms",
          observed_at: observed_at
        }
        |> Event.from_operational_observable_metric_sample()
        |> OperationalEvents.persist_event()
        |> then(fn {:ok, event} -> event end)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Live Ingress Latency Evidence",
          widgets: [
            %{
              type: :time_series,
              title: "Live Ingress Latency",
              binding: %{
                source: :operational_observables,
                observables: ["ingress.processing_latency_ms"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      latency_widget = render_item_by_title(document, "Live Ingress Latency").widget
      latency_widget_id = latency_widget.widget_id

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=source_endpoint&scope_id=#{source_endpoint.source_endpoint_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      frame_button_selector =
        ~s(#widget-#{latency_widget_id} [data-widget-frame-evidence][phx-value-observable-id="ingress.processing_latency_ms"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-scope-kind="source_endpoint"][phx-value-scope-id="#{source_endpoint.source_endpoint_id}"])

      assert has_element?(view, frame_button_selector)

      view
      |> element(frame_button_selector)
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(latency_widget_id)}"

      assert evidence_path =~
               "selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"

      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "selected_realm=flight"
      assert evidence_path =~ "scope_kind=source_endpoint"
      assert evidence_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      metric_event_id = metric_event.event_id
      metric_event_route_id = URI.encode_www_form(metric_event_id)
      metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

      metric_event_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

      assert has_element?(view, metric_event_selector)

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      metric_operational_event_evidence =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(metric_event_selector)

      assert ["operational_event"] =
               LazyHTML.attribute(metric_operational_event_evidence, "phx-value-target")

      assert [^metric_event_id] =
               LazyHTML.attribute(metric_operational_event_evidence, "phx-value-target-id")

      assert ["evidence-ref:operational_event:" <> _] =
               LazyHTML.attribute(metric_operational_event_evidence, "phx-value-link-id")

      view
      |> element(metric_event_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
        "target" => "operational_event",
        "target-id" => metric_event_id,
        "timestamp-ms" => metric_event_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables",
        "scope-kind" => "source_endpoint",
        "scope-id" => source_endpoint.source_endpoint_id,
        "resource-id" => source_endpoint.source_endpoint_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      metric_event_path = assert_patch(view)
      assert metric_event_path =~ "panel=data_link"
      assert metric_event_path =~ "selected_target=operational_event"
      assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
      assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
      assert metric_event_path =~ "time_mode=live"
      assert metric_event_path =~ "scope_kind=source_endpoint"
      assert metric_event_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      metric_event_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert metric_event_copied_path =~ "panel=data_link"
      assert metric_event_copied_path =~ "selected_target=operational_event"
      assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
      assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
      assert metric_event_copied_path =~ "data_source_id=managed_operational_observables"

      assert metric_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      assert metric_event_copied_path =~ "scope_kind=source_endpoint"
      assert metric_event_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

      {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"])
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
               "ingress-latency-live-rendered-alpha"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
               "ingress.processing_latency_ms"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
               "source_endpoint"
             )

      assert has_element?(
               reopened_metric_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      stop_dashboard_view(reopened_metric_event_view)
      stop_dashboard_view(view)
    end

    test "opens live source-endpoint command queue entry evidence from frame panel copied route" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      source_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-command-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Alpha Command Endpoint",
          metadata: %{}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-command-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Beta Command Endpoint",
          metadata: %{}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

      queue_entry =
        persist_command_queue_entry!(
          org,
          mission,
          "live-command-queue-entry-alpha",
          source_endpoint.source_endpoint_id
        )

      release_attempt = persist_command_release_attempt!(org, mission, queue_entry)

      realized_contact =
        persist_realized_contact_for_release_attempt!(org, mission, release_attempt)

      verifier_instance =
        persist_command_verifier_instance_for_release_attempt!(org, mission, release_attempt)

      transport_action_event =
        persist_transport_action_event_for_release_attempt!(org, mission, release_attempt)

      _beta_entry =
        persist_command_queue_entry!(
          org,
          mission,
          "live-command-queue-entry-beta",
          beta_endpoint.source_endpoint_id
        )

      _released_entry =
        persist_command_queue_entry!(
          org,
          mission,
          "live-command-queue-entry-released",
          source_endpoint.source_endpoint_id,
          :released
        )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Source Endpoint Command Queue",
          widgets: [
            %{
              type: :status_matrix,
              title: "Source Endpoint Command Queue",
              binding: %{
                source: :operational_observables,
                observables: ["commanding.queue_depth"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Source Endpoint Command Queue").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=source_endpoint&scope_id=#{source_endpoint.source_endpoint_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="commanding.queue_depth:#{source_endpoint.source_endpoint_id}"])

      assert has_element?(
               view,
               row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="metric_value"][data-status-matrix-realm="flight"][data-status-matrix-resource-id="#{source_endpoint.source_endpoint_id}"][data-status-matrix-scope-kind="source_endpoint"][data-status-matrix-source-endpoint-id="#{source_endpoint.source_endpoint_id}"][data-status-matrix-product-family="commanding"][data-status-matrix-supported-capability="command_queue_depth"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               view,
               row_selector <> ~s( [data-status-matrix-field="value"]),
               "1"
             )

      assert has_element?(
               view,
               row_selector <>
                 ~s( [data-status-matrix-row-evidence="commanding.queue_depth:#{source_endpoint.source_endpoint_id}"][data-status-matrix-row-evidence-observable="commanding.queue_depth"][phx-value-realm="flight"][phx-value-logical-source="operational_observables"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      view
      |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
      |> render_click()

      evidence_path = assert_patch(view)
      assert evidence_path =~ "panel=evidence"
      assert evidence_path =~ "selected_evidence_kind=frame"
      assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget.widget_id)}"
      assert evidence_path =~ "selected_observable=commanding.queue_depth"
      assert evidence_path =~ "selected_data_source=managed_operational_observables"
      assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
      assert evidence_path =~ "scope_kind=source_endpoint"
      assert evidence_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert evidence_path =~ "selected_realm=flight"

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"][data-evidence-ref-link-target="command_queue_entry"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-id="live-command-queue-entry-beta"])
             )

      refute has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-id="live-command-queue-entry-released"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("commanding.queue_depth")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      command_queue_entry_route_id = URI.encode_www_form(queue_entry.command_queue_entry_id)
      command_queue_entry_at_ms = DateTime.to_unix(queue_entry.enqueued_at, :millisecond)

      command_queue_entry_selector =
        ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"][data-evidence-ref-link-target="command_queue_entry"])

      view
      |> element(command_queue_entry_selector)
      |> render_click(%{
        "link-id" => "evidence-ref:command_queue_entry:#{queue_entry.command_queue_entry_id}",
        "target" => "command_queue_entry",
        "target-id" => queue_entry.command_queue_entry_id,
        "timestamp-ms" => command_queue_entry_at_ms,
        "realm" => "flight",
        "time-mode" => "live",
        "data-source-id" => "managed_operational_observables",
        "source-binding-id" => "default_flight_operational_observables",
        "scope-kind" => "source_endpoint",
        "scope-id" => source_endpoint.source_endpoint_id,
        "source-endpoint-id" => source_endpoint.source_endpoint_id
      })

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      command_queue_entry_path = assert_patch(view)
      assert command_queue_entry_path =~ "panel=data_link"
      assert command_queue_entry_path =~ "selected_target=command_queue_entry"
      assert command_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
      assert command_queue_entry_path =~ "selected_time=#{command_queue_entry_at_ms}"
      assert command_queue_entry_path =~ "time_mode=live"
      assert command_queue_entry_path =~ "realm=flight"
      assert command_queue_entry_path =~ "scope_kind=source_endpoint"
      assert command_queue_entry_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert command_queue_entry_path =~ "data_source_id=managed_operational_observables"

      assert command_queue_entry_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="selected_time=#{command_queue_entry_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      command_queue_entry_copied_path =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert command_queue_entry_copied_path =~ "panel=data_link"
      assert command_queue_entry_copied_path =~ "selected_target=command_queue_entry"
      assert command_queue_entry_copied_path =~ "selected_id=#{command_queue_entry_route_id}"
      assert command_queue_entry_copied_path =~ "selected_time=#{command_queue_entry_at_ms}"
      assert command_queue_entry_copied_path =~ "time_mode=live"
      assert command_queue_entry_copied_path =~ "realm=flight"
      assert command_queue_entry_copied_path =~ "scope_kind=source_endpoint"
      assert command_queue_entry_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert command_queue_entry_copied_path =~ "data_source_id=managed_operational_observables"

      assert command_queue_entry_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_command_queue_entry_view, _html} =
        live(conn, command_queue_entry_copied_path)

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="selected_time=#{command_queue_entry_at_ms}"])
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
               queue_entry.command_queue_entry_id
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
               "pending"
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Queue lane"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Priority"]),
               "3"
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Enqueued at"]),
               "2026-06-17T12:00:00"
             )

      command_request_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{queue_entry.command_request_id}"])

      assert has_element?(reopened_command_queue_entry_view, command_request_related_selector)

      reopened_command_queue_entry_view
      |> element(command_request_related_selector)
      |> render_click()

      command_request_route_id = URI.encode_www_form(queue_entry.command_request_id)
      command_request_path = assert_patch(reopened_command_queue_entry_view)
      assert command_request_path =~ "panel=data_link"
      assert command_request_path =~ "selected_target=command_request"
      assert command_request_path =~ "selected_id=#{command_request_route_id}"
      assert command_request_path =~ "nav_from_target=command_queue_entry"
      assert command_request_path =~ "nav_from_target_id=#{command_queue_entry_route_id}"
      assert command_request_path =~ "nav_trail="
      assert command_request_path =~ "time_mode=live"
      assert command_request_path =~ "realm=flight"
      assert command_request_path =~ "scope_kind=source_endpoint"
      assert command_request_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert command_request_path =~ "data_source_id=managed_operational_observables"

      assert command_request_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_command_queue_entry_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_queue_entry"][data-clipboard-text*="nav_from_target_id=#{command_queue_entry_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      command_request_copied_path =
        reopened_command_queue_entry_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert command_request_copied_path =~ "panel=data_link"
      assert command_request_copied_path =~ "selected_target=command_request"
      assert command_request_copied_path =~ "selected_id=#{command_request_route_id}"
      assert command_request_copied_path =~ "nav_from_target=command_queue_entry"
      assert command_request_copied_path =~ "nav_from_target_id=#{command_queue_entry_route_id}"
      assert command_request_copied_path =~ "time_mode=live"
      assert command_request_copied_path =~ "realm=flight"
      assert command_request_copied_path =~ "scope_kind=source_endpoint"
      assert command_request_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert command_request_copied_path =~ "data_source_id=managed_operational_observables"

      assert command_request_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_command_request_view, _html} = live(conn, command_request_copied_path)

      assert has_element?(
               reopened_command_request_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
               "queued"
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
               "NOOP"
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command id"]),
               queue_entry.command_queue_entry_id <> "-command"
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Requested at"]),
               "2026-06-17T12:00:00"
             )

      command_request_queue_entry_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{queue_entry.command_queue_entry_id}"])

      assert has_element?(
               reopened_command_request_view,
               command_request_queue_entry_related_selector
             )

      reopened_command_request_view
      |> element(command_request_queue_entry_related_selector)
      |> render_click()

      command_request_queue_entry_path = assert_patch(reopened_command_request_view)
      assert command_request_queue_entry_path =~ "panel=data_link"
      assert command_request_queue_entry_path =~ "selected_target=command_queue_entry"
      assert command_request_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
      assert command_request_queue_entry_path =~ "nav_from_target=command_request"
      assert command_request_queue_entry_path =~ "nav_from_target_id=#{command_request_route_id}"
      assert command_request_queue_entry_path =~ "time_mode=live"
      assert command_request_queue_entry_path =~ "realm=flight"
      assert command_request_queue_entry_path =~ "scope_kind=source_endpoint"
      assert command_request_queue_entry_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert command_request_queue_entry_path =~ "data_source_id=managed_operational_observables"

      assert command_request_queue_entry_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_command_request_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_request"][data-clipboard-text*="nav_from_target_id=#{command_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      command_request_queue_entry_copied_path =
        reopened_command_request_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert command_request_queue_entry_copied_path =~ "panel=data_link"
      assert command_request_queue_entry_copied_path =~ "selected_target=command_queue_entry"

      assert command_request_queue_entry_copied_path =~
               "selected_id=#{command_queue_entry_route_id}"

      assert command_request_queue_entry_copied_path =~ "nav_from_target=command_request"

      assert command_request_queue_entry_copied_path =~
               "nav_from_target_id=#{command_request_route_id}"

      assert command_request_queue_entry_copied_path =~ "time_mode=live"
      assert command_request_queue_entry_copied_path =~ "realm=flight"
      assert command_request_queue_entry_copied_path =~ "scope_kind=source_endpoint"

      assert command_request_queue_entry_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert command_request_queue_entry_copied_path =~
               "data_source_id=managed_operational_observables"

      assert command_request_queue_entry_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_command_request_queue_entry_view, _html} =
        live(conn, command_request_queue_entry_copied_path)

      assert has_element?(
               reopened_command_request_queue_entry_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_command_request_queue_entry_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_command_request_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
               queue_entry.command_queue_entry_id
             )

      assert has_element?(
               reopened_command_request_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      {:ok, reopened_command_request_for_release_view, _html} =
        live(conn, command_request_copied_path)

      command_request_release_attempt_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="command release attempt"][data-data-link-related-id="#{release_attempt.command_release_attempt_id}"])

      assert has_element?(
               reopened_command_request_for_release_view,
               command_request_release_attempt_related_selector
             )

      reopened_command_request_for_release_view
      |> element(command_request_release_attempt_related_selector)
      |> render_click()

      release_attempt_route_id = URI.encode_www_form(release_attempt.command_release_attempt_id)

      command_request_release_attempt_path =
        assert_patch(reopened_command_request_for_release_view)

      assert command_request_release_attempt_path =~ "panel=data_link"
      assert command_request_release_attempt_path =~ "selected_target=command_release_attempt"
      assert command_request_release_attempt_path =~ "selected_id=#{release_attempt_route_id}"
      assert command_request_release_attempt_path =~ "nav_from_target=command_request"

      assert command_request_release_attempt_path =~
               "nav_from_target_id=#{command_request_route_id}"

      assert command_request_release_attempt_path =~ "time_mode=live"
      assert command_request_release_attempt_path =~ "realm=flight"
      assert command_request_release_attempt_path =~ "scope_kind=source_endpoint"

      assert command_request_release_attempt_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert command_request_release_attempt_path =~
               "data_source_id=managed_operational_observables"

      assert command_request_release_attempt_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_command_request_for_release_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_command_request_for_release_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="nav_from_target=command_request"][data-clipboard-text*="nav_from_target_id=#{command_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      command_request_release_attempt_copied_path =
        reopened_command_request_for_release_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert command_request_release_attempt_copied_path =~ "panel=data_link"

      assert command_request_release_attempt_copied_path =~
               "selected_target=command_release_attempt"

      assert command_request_release_attempt_copied_path =~
               "selected_id=#{release_attempt_route_id}"

      assert command_request_release_attempt_copied_path =~ "nav_from_target=command_request"

      assert command_request_release_attempt_copied_path =~
               "nav_from_target_id=#{command_request_route_id}"

      assert command_request_release_attempt_copied_path =~ "time_mode=live"
      assert command_request_release_attempt_copied_path =~ "realm=flight"
      assert command_request_release_attempt_copied_path =~ "scope_kind=source_endpoint"

      assert command_request_release_attempt_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert command_request_release_attempt_copied_path =~
               "data_source_id=managed_operational_observables"

      assert command_request_release_attempt_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_view, _html} =
        live(conn, command_request_release_attempt_copied_path)

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
               "released"
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Verification state"]),
               "pending"
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
               queue_entry.command_queue_entry_id
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
               transport_action_request_id!(release_attempt)
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
               "start"
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
               "release_command"
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport operational event"]),
               transport_action_event.event_id
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
               "dashboard-contact-alpha"
             )

      {:ok, reopened_release_attempt_for_source_endpoint_view, _html} =
        live(conn, command_request_release_attempt_copied_path)

      release_attempt_source_endpoint_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="source endpoint"][data-data-link-related-id="#{source_endpoint.source_endpoint_id}"])

      assert has_element?(
               reopened_release_attempt_for_source_endpoint_view,
               release_attempt_source_endpoint_related_selector
             )

      reopened_release_attempt_for_source_endpoint_view
      |> element(release_attempt_source_endpoint_related_selector)
      |> render_click()

      source_endpoint_route_id = URI.encode_www_form(source_endpoint.source_endpoint_id)

      release_attempt_source_endpoint_path =
        assert_patch(reopened_release_attempt_for_source_endpoint_view)

      assert release_attempt_source_endpoint_path =~ "panel=data_link"
      assert release_attempt_source_endpoint_path =~ "selected_target=source_endpoint"
      assert release_attempt_source_endpoint_path =~ "selected_id=#{source_endpoint_route_id}"
      assert release_attempt_source_endpoint_path =~ "nav_from_target=command_release_attempt"

      assert release_attempt_source_endpoint_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_source_endpoint_path =~ "time_mode=live"
      assert release_attempt_source_endpoint_path =~ "realm=flight"
      assert release_attempt_source_endpoint_path =~ "scope_kind=source_endpoint"

      assert release_attempt_source_endpoint_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_source_endpoint_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_source_endpoint_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_for_source_endpoint_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="#{source_endpoint.source_endpoint_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_for_source_endpoint_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=source_endpoint"][data-clipboard-text*="selected_id=#{source_endpoint_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_source_endpoint_copied_path =
        reopened_release_attempt_for_source_endpoint_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_source_endpoint_copied_path =~ "panel=data_link"

      assert release_attempt_source_endpoint_copied_path =~
               "selected_target=source_endpoint"

      assert release_attempt_source_endpoint_copied_path =~
               "selected_id=#{source_endpoint_route_id}"

      assert release_attempt_source_endpoint_copied_path =~
               "nav_from_target=command_release_attempt"

      assert release_attempt_source_endpoint_copied_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_source_endpoint_copied_path =~ "time_mode=live"
      assert release_attempt_source_endpoint_copied_path =~ "realm=flight"
      assert release_attempt_source_endpoint_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_source_endpoint_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_source_endpoint_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_source_endpoint_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_source_endpoint_view, _html} =
        live(conn, release_attempt_source_endpoint_copied_path)

      assert has_element?(
               reopened_release_attempt_source_endpoint_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_source_endpoint_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="#{source_endpoint.source_endpoint_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_source_endpoint_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_release_attempt_source_endpoint_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Display name"]),
               "Alpha Command Endpoint"
             )

      reopened_release_attempt_source_endpoint_view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
      )
      |> render_click()

      source_endpoint_release_attempt_back_path =
        assert_patch(reopened_release_attempt_source_endpoint_view)

      assert source_endpoint_release_attempt_back_path =~ "panel=data_link"

      assert source_endpoint_release_attempt_back_path =~
               "selected_target=command_release_attempt"

      assert source_endpoint_release_attempt_back_path =~
               "selected_id=#{release_attempt_route_id}"

      assert source_endpoint_release_attempt_back_path =~ "time_mode=live"
      assert source_endpoint_release_attempt_back_path =~ "realm=flight"
      assert source_endpoint_release_attempt_back_path =~ "scope_kind=source_endpoint"

      assert source_endpoint_release_attempt_back_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert source_endpoint_release_attempt_back_path =~
               "data_source_id=managed_operational_observables"

      assert source_endpoint_release_attempt_back_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_source_endpoint_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_source_endpoint_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      source_endpoint_release_attempt_back_copied_path =
        reopened_release_attempt_source_endpoint_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert source_endpoint_release_attempt_back_copied_path =~ "panel=data_link"

      assert source_endpoint_release_attempt_back_copied_path =~
               "selected_target=command_release_attempt"

      assert source_endpoint_release_attempt_back_copied_path =~
               "selected_id=#{release_attempt_route_id}"

      assert source_endpoint_release_attempt_back_copied_path =~ "time_mode=live"
      assert source_endpoint_release_attempt_back_copied_path =~ "realm=flight"
      assert source_endpoint_release_attempt_back_copied_path =~ "scope_kind=source_endpoint"

      assert source_endpoint_release_attempt_back_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert source_endpoint_release_attempt_back_copied_path =~
               "data_source_id=managed_operational_observables"

      assert source_endpoint_release_attempt_back_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_source_endpoint_release_attempt_view, _html} =
        live(conn, source_endpoint_release_attempt_back_copied_path)

      assert has_element?(
               reopened_source_endpoint_release_attempt_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_source_endpoint_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_source_endpoint_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_source_endpoint_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      {:ok, reopened_release_attempt_for_contact_view, _html} =
        live(conn, command_request_release_attempt_copied_path)

      release_attempt_contact_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="contact"][data-data-link-related-id="#{realized_contact.realized_contact_id}"])

      assert has_element?(
               reopened_release_attempt_for_contact_view,
               release_attempt_contact_related_selector
             )

      reopened_release_attempt_for_contact_view
      |> element(release_attempt_contact_related_selector)
      |> render_click()

      realized_contact_route_id = URI.encode_www_form(realized_contact.realized_contact_id)
      release_attempt_contact_path = assert_patch(reopened_release_attempt_for_contact_view)

      assert release_attempt_contact_path =~ "panel=data_link"
      assert release_attempt_contact_path =~ "selected_target=contact"
      assert release_attempt_contact_path =~ "selected_id=#{realized_contact_route_id}"
      assert release_attempt_contact_path =~ "nav_from_target=command_release_attempt"

      assert release_attempt_contact_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_contact_path =~ "time_mode=live"
      assert release_attempt_contact_path =~ "realm=flight"
      assert release_attempt_contact_path =~ "scope_kind=source_endpoint"

      assert release_attempt_contact_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_contact_path =~ "data_source_id=managed_operational_observables"

      assert release_attempt_contact_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_for_contact_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="#{realized_contact.realized_contact_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_for_contact_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=contact"][data-clipboard-text*="selected_id=#{realized_contact_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_contact_copied_path =
        reopened_release_attempt_for_contact_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_contact_copied_path =~ "panel=data_link"
      assert release_attempt_contact_copied_path =~ "selected_target=contact"
      assert release_attempt_contact_copied_path =~ "selected_id=#{realized_contact_route_id}"

      assert release_attempt_contact_copied_path =~
               "nav_from_target=command_release_attempt"

      assert release_attempt_contact_copied_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_contact_copied_path =~ "time_mode=live"
      assert release_attempt_contact_copied_path =~ "realm=flight"
      assert release_attempt_contact_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_contact_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_contact_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_contact_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_contact_view, _html} =
        live(conn, release_attempt_contact_copied_path)

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="#{realized_contact.realized_contact_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
               realized_contact.realized_contact_id
             )

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Contact type"]),
               "realized_contact"
             )

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
               "active"
             )

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoints"]),
               source_endpoint.source_endpoint_id
             )

      reopened_release_attempt_contact_view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
      )
      |> render_click()

      contact_release_attempt_back_path = assert_patch(reopened_release_attempt_contact_view)
      assert contact_release_attempt_back_path =~ "panel=data_link"
      assert contact_release_attempt_back_path =~ "selected_target=command_release_attempt"
      assert contact_release_attempt_back_path =~ "selected_id=#{release_attempt_route_id}"
      assert contact_release_attempt_back_path =~ "time_mode=live"
      assert contact_release_attempt_back_path =~ "realm=flight"
      assert contact_release_attempt_back_path =~ "scope_kind=source_endpoint"

      assert contact_release_attempt_back_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert contact_release_attempt_back_path =~
               "data_source_id=managed_operational_observables"

      assert contact_release_attempt_back_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_contact_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      contact_release_attempt_back_copied_path =
        reopened_release_attempt_contact_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert contact_release_attempt_back_copied_path =~ "panel=data_link"
      assert contact_release_attempt_back_copied_path =~ "selected_target=command_release_attempt"
      assert contact_release_attempt_back_copied_path =~ "selected_id=#{release_attempt_route_id}"
      assert contact_release_attempt_back_copied_path =~ "time_mode=live"
      assert contact_release_attempt_back_copied_path =~ "realm=flight"
      assert contact_release_attempt_back_copied_path =~ "scope_kind=source_endpoint"

      assert contact_release_attempt_back_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert contact_release_attempt_back_copied_path =~
               "data_source_id=managed_operational_observables"

      assert contact_release_attempt_back_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_contact_release_attempt_view, _html} =
        live(conn, contact_release_attempt_back_copied_path)

      assert has_element?(
               reopened_contact_release_attempt_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_contact_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_contact_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_contact_release_attempt_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      transport_action_request_id = transport_action_request_id!(release_attempt)
      transport_action_request_route_id = URI.encode_www_form(transport_action_request_id)

      {:ok, reopened_release_attempt_for_verifier_view, _html} =
        live(conn, command_request_release_attempt_copied_path)

      release_attempt_verifier_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="command verifier instance"][data-data-link-related-id="#{verifier_instance.command_verifier_instance_id}"])

      assert has_element?(
               reopened_release_attempt_for_verifier_view,
               release_attempt_verifier_related_selector
             )

      reopened_release_attempt_for_verifier_view
      |> element(release_attempt_verifier_related_selector)
      |> render_click()

      verifier_instance_route_id =
        URI.encode_www_form(verifier_instance.command_verifier_instance_id)

      release_attempt_verifier_path = assert_patch(reopened_release_attempt_for_verifier_view)

      assert release_attempt_verifier_path =~ "panel=data_link"
      assert release_attempt_verifier_path =~ "selected_target=command_verifier_instance"
      assert release_attempt_verifier_path =~ "selected_id=#{verifier_instance_route_id}"
      assert release_attempt_verifier_path =~ "nav_from_target=command_release_attempt"

      assert release_attempt_verifier_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_verifier_path =~ "time_mode=live"
      assert release_attempt_verifier_path =~ "realm=flight"
      assert release_attempt_verifier_path =~ "scope_kind=source_endpoint"

      assert release_attempt_verifier_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_verifier_path =~ "data_source_id=managed_operational_observables"

      assert release_attempt_verifier_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_for_verifier_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_for_verifier_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{verifier_instance_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_verifier_copied_path =
        reopened_release_attempt_for_verifier_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_verifier_copied_path =~ "panel=data_link"

      assert release_attempt_verifier_copied_path =~
               "selected_target=command_verifier_instance"

      assert release_attempt_verifier_copied_path =~
               "selected_id=#{verifier_instance_route_id}"

      assert release_attempt_verifier_copied_path =~
               "nav_from_target=command_release_attempt"

      assert release_attempt_verifier_copied_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_verifier_copied_path =~ "time_mode=live"
      assert release_attempt_verifier_copied_path =~ "realm=flight"
      assert release_attempt_verifier_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_verifier_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_verifier_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_verifier_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_verifier_view, _html} =
        live(conn, release_attempt_verifier_copied_path)

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
               verifier_instance.command_verifier_instance_id
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Verifier name"]),
               "Live transport verifier"
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
               "satisfied"
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record kind"]),
               "transport_action_request"
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
               transport_action_request_id
             )

      verifier_transport_action_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="#{transport_action_request_id}"])

      assert has_element?(
               reopened_release_attempt_verifier_view,
               verifier_transport_action_related_selector
             )

      reopened_release_attempt_verifier_view
      |> element(verifier_transport_action_related_selector)
      |> render_click()

      verifier_transport_action_path = assert_patch(reopened_release_attempt_verifier_view)

      assert verifier_transport_action_path =~ "panel=data_link"
      assert verifier_transport_action_path =~ "selected_target=transport_action_request"
      assert verifier_transport_action_path =~ "selected_id=#{transport_action_request_route_id}"
      assert verifier_transport_action_path =~ "nav_from_target=command_verifier_instance"
      assert verifier_transport_action_path =~ "nav_from_target_id=#{verifier_instance_route_id}"
      assert verifier_transport_action_path =~ "time_mode=live"
      assert verifier_transport_action_path =~ "realm=flight"
      assert verifier_transport_action_path =~ "scope_kind=source_endpoint"
      assert verifier_transport_action_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert verifier_transport_action_path =~ "data_source_id=managed_operational_observables"

      assert verifier_transport_action_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_verifier_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_request_route_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{verifier_instance_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      verifier_transport_action_copied_path =
        reopened_release_attempt_verifier_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert verifier_transport_action_copied_path =~ "panel=data_link"

      assert verifier_transport_action_copied_path =~
               "selected_target=transport_action_request"

      assert verifier_transport_action_copied_path =~
               "selected_id=#{transport_action_request_route_id}"

      assert verifier_transport_action_copied_path =~ "nav_from_target=command_verifier_instance"

      assert verifier_transport_action_copied_path =~
               "nav_from_target_id=#{verifier_instance_route_id}"

      assert verifier_transport_action_copied_path =~ "time_mode=live"
      assert verifier_transport_action_copied_path =~ "realm=flight"
      assert verifier_transport_action_copied_path =~ "scope_kind=source_endpoint"

      assert verifier_transport_action_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert verifier_transport_action_copied_path =~
               "data_source_id=managed_operational_observables"

      assert verifier_transport_action_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_verifier_transport_action_view, _html} =
        live(conn, verifier_transport_action_copied_path)

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{verifier_instance.command_verifier_instance_id}"][phx-value-target="command_verifier_instance"])
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
               transport_action_request_id
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
               transport_action_event.event_id
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
               "start"
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
               "release_command"
             )

      verifier_transport_action_event_route_id =
        URI.encode_www_form(transport_action_event.event_id)

      verifier_transport_action_event_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{transport_action_event.event_id}"])

      assert has_element?(
               reopened_verifier_transport_action_view,
               verifier_transport_action_event_related_selector
             )

      reopened_verifier_transport_action_view
      |> element(verifier_transport_action_event_related_selector)
      |> render_click()

      verifier_transport_action_event_path =
        assert_patch(reopened_verifier_transport_action_view)

      assert verifier_transport_action_event_path =~ "panel=data_link"
      assert verifier_transport_action_event_path =~ "selected_target=operational_event"

      assert verifier_transport_action_event_path =~
               "selected_id=#{verifier_transport_action_event_route_id}"

      assert verifier_transport_action_event_path =~ "nav_from_target=transport_action_request"

      assert verifier_transport_action_event_path =~
               "nav_from_target_id=#{transport_action_request_route_id}"

      assert verifier_transport_action_event_path =~ "time_mode=live"
      assert verifier_transport_action_event_path =~ "realm=flight"
      assert verifier_transport_action_event_path =~ "scope_kind=source_endpoint"

      assert verifier_transport_action_event_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert verifier_transport_action_event_path =~
               "data_source_id=managed_operational_observables"

      assert verifier_transport_action_event_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_action_event.event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_verifier_transport_action_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{verifier_transport_action_event_route_id}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=#{transport_action_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      verifier_transport_action_event_copied_path =
        reopened_verifier_transport_action_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert verifier_transport_action_event_copied_path =~ "panel=data_link"

      assert verifier_transport_action_event_copied_path =~
               "selected_target=operational_event"

      assert verifier_transport_action_event_copied_path =~
               "selected_id=#{verifier_transport_action_event_route_id}"

      assert verifier_transport_action_event_copied_path =~
               "nav_from_target=transport_action_request"

      assert verifier_transport_action_event_copied_path =~
               "nav_from_target_id=#{transport_action_request_route_id}"

      assert verifier_transport_action_event_copied_path =~ "time_mode=live"
      assert verifier_transport_action_event_copied_path =~ "realm=flight"

      assert verifier_transport_action_event_copied_path =~
               "scope_kind=source_endpoint"

      assert verifier_transport_action_event_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert verifier_transport_action_event_copied_path =~
               "data_source_id=managed_operational_observables"

      assert verifier_transport_action_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_verifier_transport_action_event_view, _html} =
        live(conn, verifier_transport_action_event_copied_path)

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_action_event.event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_request_id}"][phx-value-target="transport_action_request"])
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{verifier_instance.command_verifier_instance_id}"][phx-value-target="command_verifier_instance"])
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
               transport_action_event.event_id
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Kind"]),
               "transport_action_requested"
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
               transport_action_request_id
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
               "start"
             )

      assert has_element?(
               reopened_verifier_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
               "release_command"
             )

      {:ok, reopened_release_attempt_for_transport_action_view, _html} =
        live(conn, command_request_release_attempt_copied_path)

      release_attempt_transport_action_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="#{transport_action_request_id}"])

      assert has_element?(
               reopened_release_attempt_for_transport_action_view,
               release_attempt_transport_action_related_selector
             )

      reopened_release_attempt_for_transport_action_view
      |> element(release_attempt_transport_action_related_selector)
      |> render_click()

      release_attempt_transport_action_path =
        assert_patch(reopened_release_attempt_for_transport_action_view)

      assert release_attempt_transport_action_path =~ "panel=data_link"
      assert release_attempt_transport_action_path =~ "selected_target=transport_action_request"

      assert release_attempt_transport_action_path =~
               "selected_id=#{transport_action_request_route_id}"

      assert release_attempt_transport_action_path =~ "nav_from_target=command_release_attempt"

      assert release_attempt_transport_action_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_transport_action_path =~ "time_mode=live"
      assert release_attempt_transport_action_path =~ "realm=flight"
      assert release_attempt_transport_action_path =~ "scope_kind=source_endpoint"

      assert release_attempt_transport_action_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_transport_action_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_transport_action_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_for_transport_action_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_for_transport_action_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_request_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_transport_action_copied_path =
        reopened_release_attempt_for_transport_action_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_transport_action_copied_path =~ "panel=data_link"

      assert release_attempt_transport_action_copied_path =~
               "selected_target=transport_action_request"

      assert release_attempt_transport_action_copied_path =~
               "selected_id=#{transport_action_request_route_id}"

      assert release_attempt_transport_action_copied_path =~
               "nav_from_target=command_release_attempt"

      assert release_attempt_transport_action_copied_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_transport_action_copied_path =~ "time_mode=live"
      assert release_attempt_transport_action_copied_path =~ "realm=flight"
      assert release_attempt_transport_action_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_transport_action_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_transport_action_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_transport_action_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_transport_action_view, _html} =
        live(conn, release_attempt_transport_action_copied_path)

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
               transport_action_request_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
               transport_action_event.event_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
               release_attempt.realized_contact_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
               release_attempt.path_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
               "live-uplink-gateway-alpha"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
               "uplink_gateway"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
               release_attempt.transport_binding_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
               "1"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
               "live-transport-activation-alpha"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
               "source_endpoint"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
               "NOOP"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
               "start"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
               "release_command"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
               "preferred_uplink_service"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
               release_attempt.command_release_attempt_id
             )

      release_attempt_transport_action_event_route_id =
        URI.encode_www_form(transport_action_event.event_id)

      release_attempt_transport_action_event_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{transport_action_event.event_id}"])

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               release_attempt_transport_action_event_related_selector
             )

      reopened_release_attempt_transport_action_view
      |> element(release_attempt_transport_action_event_related_selector)
      |> render_click()

      release_attempt_transport_action_event_path =
        assert_patch(reopened_release_attempt_transport_action_view)

      assert release_attempt_transport_action_event_path =~ "panel=data_link"

      assert release_attempt_transport_action_event_path =~
               "selected_target=operational_event"

      assert release_attempt_transport_action_event_path =~
               "selected_id=#{release_attempt_transport_action_event_route_id}"

      assert release_attempt_transport_action_event_path =~
               "nav_from_target=transport_action_request"

      assert release_attempt_transport_action_event_path =~
               "nav_from_target_id=#{transport_action_request_route_id}"

      assert release_attempt_transport_action_event_path =~ "time_mode=live"
      assert release_attempt_transport_action_event_path =~ "realm=flight"
      assert release_attempt_transport_action_event_path =~ "scope_kind=source_endpoint"

      assert release_attempt_transport_action_event_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_transport_action_event_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_transport_action_event_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_action_event.event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{release_attempt_transport_action_event_route_id}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=#{transport_action_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_transport_action_event_copied_path =
        reopened_release_attempt_transport_action_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_transport_action_event_copied_path =~ "panel=data_link"

      assert release_attempt_transport_action_event_copied_path =~
               "selected_target=operational_event"

      assert release_attempt_transport_action_event_copied_path =~
               "selected_id=#{release_attempt_transport_action_event_route_id}"

      assert release_attempt_transport_action_event_copied_path =~
               "nav_from_target=transport_action_request"

      assert release_attempt_transport_action_event_copied_path =~
               "nav_from_target_id=#{transport_action_request_route_id}"

      assert release_attempt_transport_action_event_copied_path =~ "time_mode=live"
      assert release_attempt_transport_action_event_copied_path =~ "realm=flight"

      assert release_attempt_transport_action_event_copied_path =~
               "scope_kind=source_endpoint"

      assert release_attempt_transport_action_event_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_transport_action_event_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_transport_action_event_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_transport_action_event_view, _html} =
        live(conn, release_attempt_transport_action_event_copied_path)

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_action_event.event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_request_id}"][phx-value-target="transport_action_request"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
               transport_action_event.event_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Kind"]),
               "transport_action_requested"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
               transport_action_request_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
               "start"
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
               "release_command"
             )

      reopened_release_attempt_transport_action_event_view
      |> element(
        ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"])
      )
      |> render_click()

      release_attempt_event_back_path =
        assert_patch(reopened_release_attempt_transport_action_event_view)

      assert release_attempt_event_back_path =~ "panel=data_link"
      assert release_attempt_event_back_path =~ "selected_target=command_release_attempt"
      assert release_attempt_event_back_path =~ "selected_id=#{release_attempt_route_id}"
      assert release_attempt_event_back_path =~ "time_mode=live"
      assert release_attempt_event_back_path =~ "realm=flight"
      assert release_attempt_event_back_path =~ "scope_kind=source_endpoint"

      assert release_attempt_event_back_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_event_back_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_event_back_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_transport_action_event_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_event_back_copied_path =
        reopened_release_attempt_transport_action_event_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_event_back_copied_path =~ "panel=data_link"

      assert release_attempt_event_back_copied_path =~
               "selected_target=command_release_attempt"

      assert release_attempt_event_back_copied_path =~ "selected_id=#{release_attempt_route_id}"
      assert release_attempt_event_back_copied_path =~ "time_mode=live"
      assert release_attempt_event_back_copied_path =~ "realm=flight"
      assert release_attempt_event_back_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_event_back_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_event_back_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_event_back_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_event_back_view, _html} =
        live(conn, release_attempt_event_back_copied_path)

      assert has_element?(
               reopened_release_attempt_event_back_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_event_back_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
               release_attempt.command_release_attempt_id
             )

      assert has_element?(
               reopened_release_attempt_event_back_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_release_attempt_event_back_view,
               ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
               "managed_operational_observables"
             )

      {:ok, reopened_release_attempt_for_command_request_view, _html} =
        live(conn, command_request_release_attempt_copied_path)

      release_attempt_command_request_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{queue_entry.command_request_id}"])

      assert has_element?(
               reopened_release_attempt_for_command_request_view,
               release_attempt_command_request_related_selector
             )

      reopened_release_attempt_for_command_request_view
      |> element(release_attempt_command_request_related_selector)
      |> render_click()

      release_attempt_command_request_path =
        assert_patch(reopened_release_attempt_for_command_request_view)

      assert release_attempt_command_request_path =~ "panel=data_link"
      assert release_attempt_command_request_path =~ "selected_target=command_request"
      assert release_attempt_command_request_path =~ "selected_id=#{command_request_route_id}"
      assert release_attempt_command_request_path =~ "nav_from_target=command_release_attempt"

      assert release_attempt_command_request_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_command_request_path =~ "time_mode=live"
      assert release_attempt_command_request_path =~ "realm=flight"
      assert release_attempt_command_request_path =~ "scope_kind=source_endpoint"

      assert release_attempt_command_request_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_command_request_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_command_request_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_for_command_request_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_for_command_request_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_command_request_copied_path =
        reopened_release_attempt_for_command_request_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_command_request_copied_path =~ "panel=data_link"

      assert release_attempt_command_request_copied_path =~
               "selected_target=command_request"

      assert release_attempt_command_request_copied_path =~
               "selected_id=#{command_request_route_id}"

      assert release_attempt_command_request_copied_path =~
               "nav_from_target=command_release_attempt"

      assert release_attempt_command_request_copied_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_command_request_copied_path =~ "time_mode=live"
      assert release_attempt_command_request_copied_path =~ "realm=flight"
      assert release_attempt_command_request_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_command_request_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_command_request_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_command_request_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_command_request_view, _html} =
        live(conn, release_attempt_command_request_copied_path)

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
               "queued"
             )

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
               source_endpoint.source_endpoint_id
             )

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
               "NOOP"
             )

      assert has_element?(
               reopened_release_attempt_command_request_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command id"]),
               queue_entry.command_queue_entry_id <> "-command"
             )

      release_attempt_queue_entry_related_selector =
        ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{queue_entry.command_queue_entry_id}"])

      assert has_element?(
               reopened_release_attempt_view,
               release_attempt_queue_entry_related_selector
             )

      reopened_release_attempt_view
      |> element(release_attempt_queue_entry_related_selector)
      |> render_click()

      release_attempt_queue_entry_path = assert_patch(reopened_release_attempt_view)
      assert release_attempt_queue_entry_path =~ "panel=data_link"
      assert release_attempt_queue_entry_path =~ "selected_target=command_queue_entry"
      assert release_attempt_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
      assert release_attempt_queue_entry_path =~ "nav_from_target=command_release_attempt"
      assert release_attempt_queue_entry_path =~ "nav_from_target_id=#{release_attempt_route_id}"
      assert release_attempt_queue_entry_path =~ "time_mode=live"
      assert release_attempt_queue_entry_path =~ "realm=flight"
      assert release_attempt_queue_entry_path =~ "scope_kind=source_endpoint"
      assert release_attempt_queue_entry_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
      assert release_attempt_queue_entry_path =~ "data_source_id=managed_operational_observables"

      assert release_attempt_queue_entry_path =~
               "source_binding_id=default_flight_operational_observables"

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
             )

      release_attempt_queue_entry_copied_path =
        reopened_release_attempt_view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#dashboard-data-link-copy-link")
        |> LazyHTML.attribute("data-clipboard-text")
        |> List.first()

      assert release_attempt_queue_entry_copied_path =~ "panel=data_link"
      assert release_attempt_queue_entry_copied_path =~ "selected_target=command_queue_entry"

      assert release_attempt_queue_entry_copied_path =~
               "selected_id=#{command_queue_entry_route_id}"

      assert release_attempt_queue_entry_copied_path =~ "nav_from_target=command_release_attempt"

      assert release_attempt_queue_entry_copied_path =~
               "nav_from_target_id=#{release_attempt_route_id}"

      assert release_attempt_queue_entry_copied_path =~ "time_mode=live"
      assert release_attempt_queue_entry_copied_path =~ "realm=flight"
      assert release_attempt_queue_entry_copied_path =~ "scope_kind=source_endpoint"

      assert release_attempt_queue_entry_copied_path =~
               "scope_id=#{source_endpoint.source_endpoint_id}"

      assert release_attempt_queue_entry_copied_path =~
               "data_source_id=managed_operational_observables"

      assert release_attempt_queue_entry_copied_path =~
               "source_binding_id=default_flight_operational_observables"

      {:ok, reopened_release_attempt_queue_entry_view, _html} =
        live(conn, release_attempt_queue_entry_copied_path)

      assert has_element?(
               reopened_release_attempt_queue_entry_view,
               ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
             )

      assert has_element?(
               reopened_release_attempt_queue_entry_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
             )

      assert has_element?(
               reopened_release_attempt_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
               queue_entry.command_queue_entry_id
             )

      assert has_element?(
               reopened_release_attempt_queue_entry_view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
               queue_entry.command_request_id
             )

      stop_dashboard_view(reopened_release_attempt_queue_entry_view)
      stop_dashboard_view(reopened_release_attempt_command_request_view)
      stop_dashboard_view(reopened_release_attempt_for_command_request_view)
      stop_dashboard_view(reopened_release_attempt_event_back_view)
      stop_dashboard_view(reopened_release_attempt_transport_action_event_view)
      stop_dashboard_view(reopened_release_attempt_transport_action_view)
      stop_dashboard_view(reopened_release_attempt_for_transport_action_view)
      stop_dashboard_view(reopened_verifier_transport_action_event_view)
      stop_dashboard_view(reopened_verifier_transport_action_view)
      stop_dashboard_view(reopened_release_attempt_verifier_view)
      stop_dashboard_view(reopened_release_attempt_for_verifier_view)
      stop_dashboard_view(reopened_contact_release_attempt_view)
      stop_dashboard_view(reopened_release_attempt_contact_view)
      stop_dashboard_view(reopened_release_attempt_for_contact_view)
      stop_dashboard_view(reopened_source_endpoint_release_attempt_view)
      stop_dashboard_view(reopened_release_attempt_source_endpoint_view)
      stop_dashboard_view(reopened_release_attempt_for_source_endpoint_view)
      stop_dashboard_view(reopened_release_attempt_view)
      stop_dashboard_view(reopened_command_request_for_release_view)
      stop_dashboard_view(reopened_command_request_queue_entry_view)
      stop_dashboard_view(reopened_command_request_view)
      stop_dashboard_view(reopened_command_queue_entry_view)
      stop_dashboard_view(view)
    end
  end
end
