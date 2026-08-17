defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeFixtures do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandVerifierInstance,
    CommandVerifierInstanceRow
  }

  alias Cadence.Contacts.{Path, RealizedContact}
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.OperationalEvents.Event
  alias Cadence.OperationalEvents.EventRow, as: OperationalEventRow

  alias Cadence.Repo
  alias Cadence.Runtime.TransportActionRequest
  alias CadenceWeb.TestFixtures

  def signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  def signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  def show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
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

  def render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
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

  def persist_command_queue_entry!(
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
        mission_model_revision_id: "#{command_queue_entry_id}-model",
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

  def persist_command_release_attempt!(org, mission, queue_entry) do
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
        mission_model_revision_id: "#{queue_entry.command_queue_entry_id}-model",
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

  def persist_transport_action_event_for_release_attempt!(org, mission, release_attempt) do
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

  def transport_action_request_id!(release_attempt) do
    release_attempt.metadata["transport_action_request_id"] ||
      release_attempt.metadata[:transport_action_request_id]
  end

  def persist_realized_contact_for_release_attempt!(org, mission, release_attempt) do
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
             Cadence.Contacts.persist_realized_contact(org.organization_id, realized_contact)

    persisted_contact
  end

  def persist_command_verifier_instance_for_release_attempt!(org, mission, release_attempt) do
    matched_at = DateTime.add(release_attempt.attempted_at, 5, :second)

    verifier_instance =
      CommandVerifierInstance.new(%{
        command_verifier_instance_id:
          "#{release_attempt.command_release_attempt_id}-verifier-instance",
        mission_id: mission.mission_id,
        command_request_id: release_attempt.command_request_id,
        command_release_attempt_id: release_attempt.command_release_attempt_id,
        source_endpoint_ref: release_attempt.source_endpoint_ref,
        mission_model_revision_id: release_attempt.mission_model_revision_id,
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
end
