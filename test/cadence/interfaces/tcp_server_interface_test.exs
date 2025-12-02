defmodule Cadence.Interfaces.TcpServerInterfaceTest do
  use Cadence.DataCase, async: false

  alias Cadence.Interfaces.TcpServerInterface
  alias Cadence.Missions.MissionSupervisor
  alias Cadence.TestHelpers

  @moduletag :integration

  setup do
    # Allow spawned processes to access database
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})

    # Create test organization, mission, and target
    setup_result = TestHelpers.full_test_setup()
    mission = setup_result.mission
    target = hd(setup_result.targets)

    # Start the mission supervision tree (required for protocol chain supervisor)
    {:ok, _pid} = MissionSupervisor.start_mission(mission)

    # Pick a random port to avoid conflicts
    port = Enum.random(10000..60000)

    config = %{
      bind_port: port,
      bind_address: "127.0.0.1",
      target_ids: [target.identifier],
      max_clients: 10
    }

    on_exit(fn ->
      MissionSupervisor.stop_mission(mission.id)
    end)

    {:ok, mission: mission, target: target, config: config, port: port}
  end

  describe "TCP Server Interface" do
    test "starts and listens on configured port", %{mission: mission, config: config} do
      interface_id = Ecto.UUID.generate()

      {:ok, pid} =
        TcpServerInterface.start_link(
          mission_id: mission.id,
          interface_id: interface_id,
          name: "test-tcp-server",
          config: config
        )

      # Give it a moment to start listening
      Process.sleep(100)

      stats = TcpServerInterface.stats(pid)

      assert stats.listening == true
      assert stats.bind_port == config.bind_port
      assert stats.connected_clients == 0

      GenServer.stop(pid)
    end

    test "accepts client connections", %{mission: mission, config: config, port: port} do
      interface_id = Ecto.UUID.generate()

      {:ok, server_pid} =
        TcpServerInterface.start_link(
          mission_id: mission.id,
          interface_id: interface_id,
          name: "test-tcp-server",
          config: config
        )

      # Give server time to start listening
      Process.sleep(100)

      # Connect as a client
      {:ok, client_socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

      # Give server time to accept
      Process.sleep(100)

      stats = TcpServerInterface.stats(server_pid)
      assert stats.connected_clients == 1
      assert stats.total_clients_connected == 1

      # Clean up
      :gen_tcp.close(client_socket)
      GenServer.stop(server_pid)
    end

    test "accepts multiple client connections", %{mission: mission, config: config, port: port} do
      interface_id = Ecto.UUID.generate()

      {:ok, server_pid} =
        TcpServerInterface.start_link(
          mission_id: mission.id,
          interface_id: interface_id,
          name: "test-tcp-server",
          config: config
        )

      # Give server time to start listening
      Process.sleep(100)

      # Connect multiple clients
      {:ok, client1} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      {:ok, client2} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      {:ok, client3} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

      # Give server time to accept all connections
      Process.sleep(200)

      stats = TcpServerInterface.stats(server_pid)
      assert stats.connected_clients == 3
      assert stats.total_clients_connected == 3

      clients = TcpServerInterface.list_clients(server_pid)
      assert length(clients) == 3

      # Verify each client has stats
      Enum.each(clients, fn client ->
        assert client.remote_address != nil
        assert client.remote_port != nil
        assert client.connected_at != nil
      end)

      # Clean up
      :gen_tcp.close(client1)
      :gen_tcp.close(client2)
      :gen_tcp.close(client3)
      GenServer.stop(server_pid)
    end

    test "handles client disconnections", %{mission: mission, config: config, port: port} do
      interface_id = Ecto.UUID.generate()

      {:ok, server_pid} =
        TcpServerInterface.start_link(
          mission_id: mission.id,
          interface_id: interface_id,
          name: "test-tcp-server",
          config: config
        )

      # Give server time to start listening
      Process.sleep(100)

      # Connect clients
      {:ok, client1} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      {:ok, client2} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

      Process.sleep(100)

      stats = TcpServerInterface.stats(server_pid)
      assert stats.connected_clients == 2

      # Disconnect one client
      :gen_tcp.close(client1)
      Process.sleep(100)

      stats = TcpServerInterface.stats(server_pid)
      assert stats.connected_clients == 1
      assert stats.total_clients_connected == 2

      # Clean up
      :gen_tcp.close(client2)
      GenServer.stop(server_pid)
    end

    test "receives and tracks data from clients", %{mission: mission, config: config, port: port} do
      interface_id = Ecto.UUID.generate()

      {:ok, server_pid} =
        TcpServerInterface.start_link(
          mission_id: mission.id,
          interface_id: interface_id,
          name: "test-tcp-server",
          config: config
        )

      # Give server time to start listening
      Process.sleep(100)

      # Connect as a client
      {:ok, client_socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      Process.sleep(100)

      # Send some data
      test_data = "Hello from client!"
      :gen_tcp.send(client_socket, test_data)

      # Give server time to process
      Process.sleep(100)

      stats = TcpServerInterface.stats(server_pid)
      assert stats.bytes_received >= byte_size(test_data)

      # Clean up
      :gen_tcp.close(client_socket)
      GenServer.stop(server_pid)
    end

    test "enforces max_clients limit", %{mission: mission, config: config, port: port} do
      # Set max clients to 2
      limited_config = Map.put(config, :max_clients, 2)
      interface_id = Ecto.UUID.generate()

      {:ok, server_pid} =
        TcpServerInterface.start_link(
          mission_id: mission.id,
          interface_id: interface_id,
          name: "test-tcp-server",
          config: limited_config
        )

      Process.sleep(100)

      # Connect 2 clients (should succeed)
      {:ok, client1} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      {:ok, client2} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      Process.sleep(100)

      stats = TcpServerInterface.stats(server_pid)
      assert stats.connected_clients == 2

      # Try to connect a 3rd client (should be rejected)
      {:ok, client3} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
      Process.sleep(100)

      # Server should still have only 2 clients
      stats = TcpServerInterface.stats(server_pid)
      assert stats.connected_clients == 2

      # Client 3 should be closed by server
      assert :gen_tcp.recv(client3, 0, 100) == {:error, :closed}

      # Clean up
      :gen_tcp.close(client1)
      :gen_tcp.close(client2)
      GenServer.stop(server_pid)
    end
  end
end
