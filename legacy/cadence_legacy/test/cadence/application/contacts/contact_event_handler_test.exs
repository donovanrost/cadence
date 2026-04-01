defmodule Cadence.Application.Contacts.ContactEventHandlerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Application.Contacts.ContactEventHandler
  alias Cadence.Buckets
  alias Cadence.Recordings.Recording
  alias Ecto.Adapters.SQL.Sandbox

  alias Cadence.Recordings.Recordables.{
    ContactActionCompleted,
    ContactActionFailed,
    ContactActionSkipped,
    ContactActivationFailed,
    ContactBlocked,
    ContactEnded,
    ContactReady,
    ContactSkipped,
    ContactStarted
  }

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures

  test "records contact lifecycle and action events" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    {:ok, bucket} =
      Buckets.create_bucket_with_path(%{
        organization_id: org.id,
        mission_id: mission.id,
        bucket_type: "mission",
        bucketable_type: "Mission",
        bucketable_id: mission.id,
        name: mission.name
      })

    pid =
      case start_supervised({ContactEventHandler, subscribe?: false}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Sandbox.allow(Cadence.Repo, self(), pid)

    contact_id = Ecto.UUID.generate()
    spacecraft_id = Ecto.UUID.generate()
    ground_station_id = Ecto.UUID.generate()

    base_payload = %{
      organization_id: org.id,
      mission_id: mission.id,
      contact_id: contact_id,
      spacecraft_target_id: spacecraft_id,
      ground_station_target_id: ground_station_id,
      antenna_id: "ant-1",
      direction: :uplink
    }

    send(
      pid,
      {:contact_lifecycle, :contact_started,
       Map.put(base_payload, :resolved_transport_ids, [Ecto.UUID.generate()])}
    )

    send(pid, {:contact_lifecycle, :contact_ended, Map.put(base_payload, :reason, "completed")})

    send(
      pid,
      {:contact_lifecycle, :contact_activation_failed,
       base_payload
       |> Map.put(:error_code, "missing_transport")
       |> Map.put(:error_message, "No transport configured")
       |> Map.put(:details, %{missing: "uplink_transport_id"})}
    )

    send(
      pid,
      {:contact_lifecycle, :contact_blocked,
       base_payload
       |> Map.put(:blocked_by_contact_id, Ecto.UUID.generate())
       |> Map.put(:policy, "no_preemption_priority")
       |> Map.put(:message, "Resource held")}
    )

    send(
      pid,
      {:contact_lifecycle, :contact_skipped,
       Map.put(base_payload, :reason, "resource_unavailable")}
    )

    action_id = Ecto.UUID.generate()

    send(
      pid,
      {:contact_readiness, :contact_ready,
       base_payload
       |> Map.put(:gate, "uplink_ready")
       |> Map.put(:details, %{transport_id: Ecto.UUID.generate()})}
    )

    send(
      pid,
      {:contact_action, :contact_action_completed,
       base_payload
       |> Map.put(:contact_action_id, action_id)
       |> Map.put(:result, %{command_log_id: "cmd-123"})}
    )

    send(
      pid,
      {:contact_action, :contact_action_failed,
       base_payload
       |> Map.put(:contact_action_id, Ecto.UUID.generate())
       |> Map.put(:error_code, "dispatch_failed")
       |> Map.put(:error_message, "Dispatcher unavailable")}
    )

    send(
      pid,
      {:contact_action, :contact_action_skipped,
       base_payload
       |> Map.put(:contact_action_id, Ecto.UUID.generate())
       |> Map.put(:reason, "contact_ended")}
    )

    assert eventually(fn -> Repo.aggregate(ContactStarted, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactEnded, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactActivationFailed, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactBlocked, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactSkipped, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactReady, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactActionCompleted, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactActionFailed, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactActionSkipped, :count) == 1 end)

    recordings = Repo.all(Recording)
    recordable_types = Enum.map(recordings, & &1.recordable_type)

    assert "ContactStarted" in recordable_types
    assert "ContactEnded" in recordable_types
    assert "ContactActivationFailed" in recordable_types
    assert "ContactBlocked" in recordable_types
    assert "ContactSkipped" in recordable_types
    assert "ContactReady" in recordable_types
    assert "ContactActionCompleted" in recordable_types
    assert "ContactActionFailed" in recordable_types
    assert "ContactActionSkipped" in recordable_types

    assert Enum.all?(recordings, fn recording -> recording.bucket_id == bucket.id end)
  end

  test "records events with string-key payloads" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    {:ok, bucket} =
      Buckets.create_bucket_with_path(%{
        organization_id: org.id,
        mission_id: mission.id,
        bucket_type: "mission",
        bucketable_type: "Mission",
        bucketable_id: mission.id,
        name: mission.name
      })

    pid =
      case start_supervised({ContactEventHandler, subscribe?: false}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Sandbox.allow(Cadence.Repo, self(), pid)

    payload = %{
      "organization_id" => org.id,
      "mission_id" => mission.id,
      "contact_id" => Ecto.UUID.generate(),
      "gate" => "uplink_ready"
    }

    send(pid, {:contact_readiness, :contact_ready, payload})

    assert eventually(fn -> Repo.aggregate(ContactReady, :count) == 1 end)

    recording = Repo.one(Recording)
    assert recording.bucket_id == bucket.id
  end

  test "MissionTracker starts before ContactEventHandler in application children" do
    children = Cadence.Application.base_children()

    mission_tracker_index =
      Enum.find_index(children, fn
        {Cadence.Runtime.Missions.MissionTracker, _opts} -> true
        _other -> false
      end)

    contact_event_handler_index =
      Enum.find_index(children, &(&1 == Cadence.Application.Contacts.ContactEventHandler))

    assert is_integer(mission_tracker_index)
    assert is_integer(contact_event_handler_index)
    assert mission_tracker_index < contact_event_handler_index
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end
end
