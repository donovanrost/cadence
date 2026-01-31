defmodule Cadence.Runtime.Contacts.ContactSchedulerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Contacts.ContactScheduler
  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Transports.Interface

  @receive_timeout 500

  setup_virtual_time()
  setup_mission_registry()

  setup do
    if is_nil(Process.whereis(Cadence.PubSub)) do
      start_supervised!({Phoenix.PubSub, name: Cadence.PubSub})
    end

    :persistent_term.put({__MODULE__.TestInterfaceSupervisor, :test_pid}, self())

    on_exit(fn ->
      :persistent_term.erase({__MODULE__.TestInterfaceSupervisor, :test_pid})
    end)

    :ok
  end

  test "contact starts and ends transports" do
    mission_id = "mission-1"
    organization_id = "org-1"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 10, :second),
      end_time: DateTime.add(now, 20, :second),
      direction: :uplink,
      state: :planned
    }

    profile = %{
      id: Ecto.UUID.generate(),
      ground_station_target_id: contact.ground_station_target_id,
      resources: %{
        "antennas" => [
          %{
            "id" => "ant-1",
            "activation" => %{
              "uplink_transport_id" => transport_id
            }
          }
        ]
      }
    }

    transport = %Interface{id: transport_id, enabled: true, name: "Uplink", type: :tcp}

    store_bundle(mission_id, organization_id, [contact], [profile], [transport])

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, pid} =
      start_supervised(
        {ContactScheduler,
         mission_id: mission_id,
         organization_id: organization_id,
         interface_supervisor: __MODULE__.TestInterfaceSupervisor}
      )

    :ok = GenServer.call(pid, :sync)
    Time.advance(10_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:ensure_started, ^transport_id}, @receive_timeout
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact.id
    Time.advance(10_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_ended, payload}, @receive_timeout
    assert payload.contact_id == contact.id
    assert_receive {:ensure_stopped, ^transport_id}, @receive_timeout
  end

  test "overlapping contacts share transport and stop after both end" do
    mission_id = "mission-2"
    organization_id = "org-2"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact_one = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, -1, :second),
      end_time: DateTime.add(now, 10, :second),
      direction: :uplink,
      state: :planned
    }

    contact_two = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 5, :second),
      end_time: DateTime.add(now, 15, :second),
      direction: :uplink,
      state: :planned
    }

    profile = %{
      id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      resources: %{
        "antennas" => [
          %{
            "id" => "ant-1",
            "activation" => %{
              "uplink_transport_id" => transport_id
            }
          }
        ]
      }
    }

    transport = %Interface{id: transport_id, enabled: true, name: "Uplink", type: :tcp}

    store_bundle(mission_id, organization_id, [contact_one, contact_two], [profile], [transport])

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, pid} =
      start_supervised(
        {ContactScheduler,
         mission_id: mission_id,
         organization_id: organization_id,
         interface_supervisor: __MODULE__.TestInterfaceSupervisor}
      )

    :ok = GenServer.call(pid, :sync)
    assert_receive {:ensure_started, ^transport_id}, @receive_timeout
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id

    Time.advance(5_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id
    refute_receive {:ensure_started, ^transport_id}

    Time.advance(5_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_ended, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id
    refute_receive {:ensure_stopped, ^transport_id}

    Time.advance(5_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_ended, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id
    assert_receive {:ensure_stopped, ^transport_id}, @receive_timeout
  end

  defp store_bundle(mission_id, organization_id, contacts, profiles, transports) do
    %ConfigBundle{
      mission_id: mission_id,
      organization_id: organization_id,
      config_version: 1,
      contacts: contacts,
      ground_station_profiles: profiles,
      transport_interfaces: transports
    }
    |> ConfigBundle.store()
  end

  defmodule TestInterfaceSupervisor do
    def ensure_started(_mission_id, transport_id, _transport) do
      notify({:ensure_started, transport_id})
      :ok
    end

    def ensure_stopped(_mission_id, transport_id) do
      notify({:ensure_stopped, transport_id})
      :ok
    end

    defp notify(message) do
      case :persistent_term.get({__MODULE__, :test_pid}, nil) do
        nil -> :ok
        pid -> send(pid, message)
      end
    end
  end
end
