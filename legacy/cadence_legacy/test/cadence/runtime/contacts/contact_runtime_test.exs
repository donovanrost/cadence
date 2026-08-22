defmodule Cadence.Runtime.Contacts.ContactRuntimeTest do
  use Cadence.PureCase, async: false

  alias Cadence.Contacts.Contact
  alias Cadence.Contacts.ContactCommandAction
  alias Cadence.Harness.Time
  alias Cadence.Runtime.Contacts.ContactRuntime

  setup_virtual_time()
  setup_mission_registry()

  defmodule ActionClaimerOk do
    def claim(_action, _context), do: :ok
  end

  defmodule ActionClaimerAlreadyClaimed do
    def claim(_action, _context), do: {:error, :already_claimed}
  end

  defmodule ActionClaimerUnavailable do
    def claim(_action, _context), do: {:error, :unavailable}
  end

  defmodule ActionExecutorOk do
    def execute(_action, _context), do: {:ok, %{command_log_id: "cmd-123"}}
  end

  defmodule ActionExecutorFail do
    def execute(_action, _context), do: {:error, :dispatch_failed}
  end

  test "dispatches action when uplink_ready becomes true" do
    mission_id = Ecto.UUID.generate()
    org_id = Ecto.UUID.generate()
    contact_id = Ecto.UUID.generate()
    transport_id = Ecto.UUID.generate()

    contact = %Contact{
      id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      direction: :uplink
    }

    action = %ContactCommandAction{
      id: Ecto.UUID.generate(),
      contact_id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      gate: :uplink_ready,
      order: 0,
      state: :planned,
      command_ref: %{"command_name" => "PING", "parameters" => %{}}
    }

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, _pid} =
      start_supervised(
        {ContactRuntime,
         mission_id: mission_id,
         organization_id: org_id,
         contact: contact,
         transport_ids: [transport_id],
         uplink_transport_id: transport_id,
         actions: [action],
         action_claimer: ActionClaimerOk,
         action_executor: ActionExecutorOk}
      )

    ContactRuntime.signal(mission_id, contact_id, {:transport_connected, transport_id, true})

    assert_receive({:contact_action, :contact_action_completed, payload}, 1_000)
    assert payload.contact_action_id == action.id
  end

  test "does not dispatch when already claimed" do
    mission_id = Ecto.UUID.generate()
    org_id = Ecto.UUID.generate()
    contact_id = Ecto.UUID.generate()
    transport_id = Ecto.UUID.generate()

    contact = %Contact{
      id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      direction: :uplink
    }

    action = %ContactCommandAction{
      id: Ecto.UUID.generate(),
      contact_id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      gate: :uplink_ready,
      order: 0,
      state: :planned,
      command_ref: %{"command_name" => "PING", "parameters" => %{}}
    }

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, _pid} =
      start_supervised(
        {ContactRuntime,
         mission_id: mission_id,
         organization_id: org_id,
         contact: contact,
         transport_ids: [transport_id],
         uplink_transport_id: transport_id,
         actions: [action],
         action_claimer: ActionClaimerAlreadyClaimed,
         action_executor: ActionExecutorOk}
      )

    ContactRuntime.signal(mission_id, contact_id, {:transport_connected, transport_id, true})

    refute_receive({:contact_action, :contact_action_completed, _payload}, 200)
  end

  test "retries until contact end and skips when control plane unavailable" do
    mission_id = Ecto.UUID.generate()
    org_id = Ecto.UUID.generate()
    contact_id = Ecto.UUID.generate()
    transport_id = Ecto.UUID.generate()

    contact = %Contact{
      id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      direction: :uplink
    }

    action = %ContactCommandAction{
      id: Ecto.UUID.generate(),
      contact_id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      gate: :uplink_ready,
      order: 0,
      state: :planned,
      command_ref: %{"command_name" => "PING", "parameters" => %{}}
    }

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, _pid} =
      start_supervised(
        {ContactRuntime,
         mission_id: mission_id,
         organization_id: org_id,
         contact: contact,
         transport_ids: [transport_id],
         uplink_transport_id: transport_id,
         actions: [action],
         action_claimer: ActionClaimerUnavailable,
         action_executor: ActionExecutorOk,
         retry_interval_ms: 100}
      )

    ContactRuntime.signal(mission_id, contact_id, {:transport_connected, transport_id, true})

    :ok = Time.advance(100)
    ContactRuntime.end_contact(mission_id, contact_id)

    assert_receive({:contact_action, :contact_action_skipped, payload}, 1_000)
    assert payload.reason == "control_plane_unavailable"
  end

  test "skips pending actions when contact ends before ready" do
    mission_id = Ecto.UUID.generate()
    org_id = Ecto.UUID.generate()
    contact_id = Ecto.UUID.generate()

    contact = %Contact{
      id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      direction: :uplink
    }

    action = %ContactCommandAction{
      id: Ecto.UUID.generate(),
      contact_id: contact_id,
      mission_id: mission_id,
      organization_id: org_id,
      gate: :uplink_ready,
      order: 0,
      state: :planned,
      command_ref: %{"command_name" => "PING", "parameters" => %{}}
    }

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, _pid} =
      start_supervised(
        {ContactRuntime,
         mission_id: mission_id,
         organization_id: org_id,
         contact: contact,
         transport_ids: [],
         uplink_transport_id: nil,
         actions: [action],
         action_claimer: ActionClaimerOk,
         action_executor: ActionExecutorFail}
      )

    ContactRuntime.end_contact(mission_id, contact_id)

    assert_receive({:contact_action, :contact_action_skipped, payload}, 1_000)
    assert payload.reason == "contact_ended"
  end
end
