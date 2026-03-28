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

  test "contention chooses higher priority and blocks lower priority contact" do
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
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 10, :second),
      direction: :uplink,
      priority: 5,
      state: :planned
    }

    contact_two = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 12, :second),
      direction: :uplink,
      priority: 1,
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
    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:ensure_started, ^transport_id}, @receive_timeout
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id

    contact_two_id = contact_two.id

    assert_receive {:contact_lifecycle, :contact_blocked, payload}, @receive_timeout
    assert payload.contact_id == contact_two_id
    assert payload.blocked_by_contact_id == contact_one.id
    refute_receive {:contact_lifecycle, :contact_started, %{contact_id: ^contact_two_id}}
  end

  test "blocked contact starts after resource is freed" do
    mission_id = "mission-3"
    organization_id = "org-3"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact_one = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 6, :second),
      direction: :uplink,
      priority: 2,
      state: :planned
    }

    contact_two = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 2, :second),
      end_time: DateTime.add(now, 10, :second),
      direction: :uplink,
      priority: 1,
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
    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id

    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_blocked, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id

    Time.advance(4_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_ended, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id

    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id
  end

  test "blocked contact is skipped when the window expires" do
    mission_id = "mission-4"
    organization_id = "org-4"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact_one = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 10, :second),
      direction: :uplink,
      priority: 2,
      state: :planned
    }

    contact_two = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 2, :second),
      end_time: DateTime.add(now, 5, :second),
      direction: :uplink,
      priority: 1,
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
    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id

    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_blocked, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id

    Time.advance(3_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_skipped, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id
  end

  test "tie-breaks by earliest start time then lowest id" do
    mission_id = "mission-5"
    organization_id = "org-5"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact_one = %{
      id: "00000000-0000-0000-0000-000000000001",
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 6, :second),
      direction: :uplink,
      priority: 1,
      state: :planned
    }

    contact_two = %{
      id: "00000000-0000-0000-0000-000000000002",
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 6, :second),
      direction: :uplink,
      priority: 1,
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

    store_bundle(mission_id, organization_id, [contact_two, contact_one], [profile], [transport])

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")

    {:ok, pid} =
      start_supervised(
        {ContactScheduler,
         mission_id: mission_id,
         organization_id: organization_id,
         interface_supervisor: __MODULE__.TestInterfaceSupervisor}
      )

    :ok = GenServer.call(pid, :sync)
    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id
  end

  test "active-on-boot contact starts immediately" do
    mission_id = "mission-boot"
    organization_id = "org-boot"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, -5, :second),
      end_time: DateTime.add(now, 30, :second),
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

    assert_receive {:ensure_started, ^transport_id}, @receive_timeout
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact.id
  end

  test "overlapping contacts on different antennas share transport refcount" do
    mission_id = "mission-2b"
    organization_id = "org-2b"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact_one = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: Ecto.UUID.generate(),
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 10, :second),
      direction: :uplink,
      priority: 1,
      state: :planned
    }

    contact_two = %{
      id: Ecto.UUID.generate(),
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: contact_one.ground_station_target_id,
      antenna_id: "ant-2",
      start_time: DateTime.add(now, 1, :second),
      end_time: DateTime.add(now, 12, :second),
      direction: :uplink,
      priority: 1,
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
          },
          %{
            "id" => "ant-2",
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
    Time.advance(1_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:ensure_started, ^transport_id}, @receive_timeout
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id in [contact_one.id, contact_two.id]
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id in [contact_one.id, contact_two.id]
    refute_receive {:ensure_started, ^transport_id}

    Time.advance(9_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_ended, payload}, @receive_timeout
    assert payload.contact_id == contact_one.id
    refute_receive {:ensure_stopped, ^transport_id}

    Time.advance(2_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:contact_lifecycle, :contact_ended, payload}, @receive_timeout
    assert payload.contact_id == contact_two.id
    assert_receive {:ensure_stopped, ^transport_id}, @receive_timeout
  end

  test "config reload reschedules timers without double-start" do
    mission_id = "mission-reload"
    organization_id = "org-reload"
    transport_id = Ecto.UUID.generate()

    now = Time.now()

    contact_id = Ecto.UUID.generate()
    ground_station_id = Ecto.UUID.generate()

    contact = %{
      id: contact_id,
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft_target_id: Ecto.UUID.generate(),
      ground_station_target_id: ground_station_id,
      antenna_id: "ant-1",
      start_time: DateTime.add(now, 10, :second),
      end_time: DateTime.add(now, 20, :second),
      direction: :uplink,
      state: :planned
    }

    profile = %{
      id: Ecto.UUID.generate(),
      ground_station_target_id: ground_station_id,
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

    updated_contact = %{
      contact
      | start_time: DateTime.add(now, 12, :second),
        end_time: DateTime.add(now, 22, :second)
    }

    store_bundle(mission_id, organization_id, [updated_contact], [profile], [transport])
    send(pid, {:config_updated, 2})
    :ok = GenServer.call(pid, :sync)

    Time.advance(10_000)
    :ok = GenServer.call(pid, :sync)

    refute_receive {:ensure_started, ^transport_id}
    refute_receive {:contact_lifecycle, :contact_started, _payload}

    Time.advance(2_000)
    :ok = GenServer.call(pid, :sync)

    assert_receive {:ensure_started, ^transport_id}, @receive_timeout
    assert_receive {:contact_lifecycle, :contact_started, payload}, @receive_timeout
    assert payload.contact_id == contact_id
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
