defmodule Cadence.Reads.OperationalState do
  @moduledoc """
  Read boundary for current operational resources and runtime state.

  Consumers receive domain records or normalized snapshots without knowing
  which owning context or store answers each query.
  """

  alias Cadence.Commanding
  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore, TransportStore}
  alias Cadence.Contacts
  alias Cadence.OperationalEvents
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.RuntimeHealth

  def list_transports(organization_id, mission_id) do
    TransportStore.list_transports(organization_id, mission_id)
  end

  def fetch_transport(organization_id, mission_id, transport_id) do
    TransportStore.fetch_transport(organization_id, mission_id, transport_id)
  end

  def fetch_ground_station(organization_id, mission_id, ground_station_id) do
    GroundStationStore.fetch_ground_station(organization_id, mission_id, ground_station_id)
  end

  def list_routing_rules(organization_id, mission_id) do
    RoutingRuleStore.list_routing_rules(organization_id, mission_id)
  end

  def list_source_endpoints(organization_id, mission_id) do
    SourceEndpoints.list_source_endpoints(organization_id, mission_id)
  end

  def fetch_source_endpoint(organization_id, mission_id, source_endpoint_id) do
    SourceEndpoints.fetch_source_endpoint(organization_id, mission_id, source_endpoint_id)
  end

  def list_spacecraft(organization_id, mission_id) do
    SpacecraftStore.list_spacecraft(organization_id, mission_id)
  end

  def list_scheduled_contacts(organization_id, mission_id) do
    Contacts.list_scheduled_contacts(organization_id, mission_id)
  end

  def list_realized_contacts(organization_id, mission_id) do
    Contacts.list_realized_contacts(organization_id, mission_id)
  end

  def fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id) do
    Contacts.fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id)
  end

  def fetch_realized_contact(organization_id, mission_id, realized_contact_id) do
    Contacts.fetch_realized_contact(organization_id, mission_id, realized_contact_id)
  end

  def fetch_link_assignment(organization_id, mission_id, link_assignment_id) do
    Contacts.fetch_link_assignment(organization_id, mission_id, link_assignment_id)
  end

  def list_pending_command_queue_entries(organization_id, mission_id) do
    Commanding.list_command_queue_entries(organization_id, mission_id, lifecycle_state: :pending)
  end

  def list_command_verifier_instances(
        organization_id,
        mission_id,
        command_release_attempt_id
      ) do
    Commanding.list_command_verifier_instances(organization_id, mission_id,
      command_release_attempt_id: command_release_attempt_id
    )
  end

  def list_operational_events(organization_id, mission_id, opts) do
    OperationalEvents.list_events(organization_id, mission_id, opts)
  end

  def transport_execution_intervals(organization_id, mission_id, opts) do
    OperationalEvents.transport_execution_intervals(organization_id, mission_id, opts)
  end

  def ingress_processing_latency_snapshots do
    RuntimeHealth.snapshot()
    |> Map.get(:metrics, %{})
    |> Map.get(:ingress_processing_latency_ms, [])
  end
end
