defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import ExUnit.Callbacks
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  def assert_transport_action_runtime_context!(
        view,
        release_attempt_id,
        command_request_id,
        replay_run_id
      ) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             command_request_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             release_attempt_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  def assert_live_transport_action_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             "release-attempt-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             "command-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-live-1"
           )
  end

  def assert_live_transport_capability_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-runtime-live-record-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "cop1_state"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "vcid"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "transport-action-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )
  end

  def assert_live_transport_timer_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"]),
             "transport-timer-event-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "cop1_timeout"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "transport-action-request-live-1"
           )
  end

  def assert_transport_timer_runtime_context!(view, replay_run_id) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"]),
             "transport-timer-event-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "cop1_timeout"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "transport-action-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  def assert_managed_timer_runtime_context!(view, replay_run_id) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"]),
             "managed-timer-event-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "flush"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "managed-action-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  def assert_live_managed_timer_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"]),
             "managed-timer-event-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "flush"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "managed-action-request-live-1"
           )
  end

  def configure_dashboard_source_health!(now) do
    previous = Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:now, now)
      |> Keyword.put(:source_health_freshness, %{default_max_age_ms: 86_400_000})
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :dashboard_engine_source_execution, previous)
    end)
  end

  def operational_observable_state_event(
        organization_id,
        mission_id,
        snapshot_id,
        state,
        observed_at,
        opts
      ) do
    transport_id = Keyword.fetch!(opts, :transport_id)
    observable_id = Keyword.get(opts, :observable_id, "comms.transport.connection_state")
    resource_id = Keyword.get(opts, :resource_id, transport_id)
    scope_kind = Keyword.get(opts, :scope_kind, :transport)

    Event.from_operational_observable_state_snapshot(%{
      snapshot_id: snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: transport_id,
      source_endpoint_id: "replay-source-health-endpoint",
      ground_station_id: "dss-14",
      link_id: Keyword.get(opts, :link_id),
      adapter_key: :tcp_socket,
      connection_state: connection_state_value(observable_id, state),
      rf_lock_state: rf_lock_state_value(observable_id, state),
      frame_sync_state: frame_sync_state_value(observable_id, state),
      state: state,
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  def connection_state_value("comms.transport.connection_state", state), do: state
  def connection_state_value("ground.station.connection_state", state), do: state
  def connection_state_value(_observable_id, _state), do: nil

  def rf_lock_state_value("link.rf_lock_state", state), do: state
  def rf_lock_state_value(_observable_id, _state), do: nil

  def frame_sync_state_value("link.frame_sync_state", state), do: state
  def frame_sync_state_value(_observable_id, _state), do: nil

  def open_and_assert_replay_rf_evidence!(view, conn, attrs) do
    row_selector = Map.fetch!(attrs, :row_selector)
    widget_id = Map.fetch!(attrs, :widget_id)
    observable_id = Map.fetch!(attrs, :observable_id)
    replay_sources = Map.fetch!(attrs, :replay_sources)
    replay_run_id = Map.fetch!(attrs, :replay_run_id)
    interval = Map.fetch!(attrs, :interval)
    expected_snapshot_id = Map.fetch!(attrs, :expected_snapshot_id)
    expected_state = Map.fetch!(attrs, :expected_state)
    expected_transport_id = Map.fetch!(attrs, :expected_transport_id)

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form(observable_id)}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="#{rf_interval_evidence_kind(observable_id)}"][data-evidence-ref-id="#{interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form(observable_id)}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    rf_operational_event_id = interval.source_event_id
    rf_operational_event_route_id = URI.encode_www_form(rf_operational_event_id)
    rf_event_at_ms = DateTime.to_unix(interval.starts_at, :millisecond)

    rf_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{rf_operational_event_id}"][data-evidence-ref-link-target="operational_event"])

    view
    |> element(rf_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{rf_operational_event_id}",
      "target" => "operational_event",
      "target-id" => rf_operational_event_id,
      "timestamp-ms" => rf_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    rf_event_path = assert_patch(view)
    assert rf_event_path =~ "panel=data_link"
    assert rf_event_path =~ "selected_target=operational_event"
    assert rf_event_path =~ "selected_id=#{rf_operational_event_route_id}"
    assert rf_event_path =~ "selected_time=#{rf_event_at_ms}"
    assert rf_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    rf_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert rf_event_copied_path =~ "panel=data_link"
    assert rf_event_copied_path =~ "selected_target=operational_event"
    assert rf_event_copied_path =~ "selected_id=#{rf_operational_event_route_id}"
    assert rf_event_copied_path =~ "selected_time=#{rf_event_at_ms}"
    assert rf_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert rf_event_copied_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert rf_event_copied_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_rf_event_view, _html} = live(conn, rf_event_copied_path)

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="selected_time=#{rf_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
             expected_snapshot_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             observable_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             expected_transport_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state"]),
             expected_state
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
             expected_snapshot_id
           )

    stop_dashboard_view(reopened_rf_event_view)
  end

  def rf_interval_evidence_kind("link.rf_lock_state"), do: "link rf lock state interval"
  def rf_interval_evidence_kind("link.frame_sync_state"), do: "link frame sync state interval"

  def show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  def element_attribute(html, selector, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    value
  end

  def fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  def replace_dashboard_row_document!(org, mission, %Document{} = document) do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{document: JsonDocument.encode(Document.to_map(document))})
    |> Repo.update!()

    document
  end

  def render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  def render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  def track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  def stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  def drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  def enable_dashboard_engine_inline_resolves! do
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
end
