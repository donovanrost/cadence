defmodule Cadence.Application.Contacts.ContactEventHandlerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Application.Contacts.ContactEventHandler
  alias Cadence.Buckets
  alias Cadence.Recordings.Recording

  alias Cadence.Recordings.Recordables.{
    ContactActivationFailed,
    ContactEnded,
    ContactStarted
  }

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures

  test "records contact lifecycle events" do
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

    Ecto.Adapters.SQL.Sandbox.allow(Cadence.Repo, self(), pid)

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

    assert eventually(fn -> Repo.aggregate(ContactStarted, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactEnded, :count) == 1 end)
    assert eventually(fn -> Repo.aggregate(ContactActivationFailed, :count) == 1 end)

    recordings = Repo.all(Recording)
    recordable_types = Enum.map(recordings, & &1.recordable_type)

    assert "ContactStarted" in recordable_types
    assert "ContactEnded" in recordable_types
    assert "ContactActivationFailed" in recordable_types

    assert Enum.all?(recordings, fn recording -> recording.bucket_id == bucket.id end)
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
