defmodule Cadence.Runtime.Interfaces.TcpServerInterfaceTest do
  use Cadence.DataCase, async: false

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.TcpServerInterface
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.TestHelpers
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :integration

  setup do
    # Allow spawned processes to access database
    Sandbox.mode(Cadence.Repo, {:shared, self()})

    # Create test organization, mission, and target
    setup_result = TestHelpers.full_test_setup()
    mission = setup_result.mission
    target = hd(setup_result.targets)

    # Start the mission supervision tree (required for protocol chain supervisor)
    {:ok, config} = MissionConfig.load(mission.id)
    {:ok, _pid} = MissionSupervisor.start_mission(config)

    # Pick a random port to avoid conflicts
    port = Enum.random(10_000..60_000)

    on_exit(fn ->
      MissionSupervisor.stop_mission(mission.id)
    end)

    {:ok, mission: mission, target: target, port: port}
  end

  # Helper to build an Interface entity for testing
  defp build_interface(mission_id, port, target_ids, opts \\ []) do
    max_clients = Keyword.get(opts, :max_clients, 10)

    %Interface{
      id: Ecto.UUID.generate(),
      mission_id: mission_id,
      name: "test-tcp-server",
      connection_type: :tcp_server,
      bind_address: "127.0.0.1",
      bind_port: port,
      target_ids: target_ids,
      config: %{max_clients: max_clients},
      protocols: []
    }
  end

  describe "TCP Server Interface" do
    test "starts and listens on configured port", %{mission: mission, target: target, port: port} do
      interface = build_interface(mission.id, port, [target.identifier])

      {:ok, pid} = TcpServerInterface.start_link(interface)

      # Give it a moment to start listening
      Process.sleep(100)

      stats = TcpServerInterface.stats(pid)

      assert stats.listening == true
      assert stats.bind_port == port
      assert stats.connected_clients == 0

      GenServer.stop(pid)
    end

    test "accepts client connections", %{mission: mission, target: target, port: port} do
      interface = build_interface(mission.id, port, [target.identifier])

      {:ok, server_pid} = TcpServerInterface.start_link(interface)

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

    test "accepts multiple client connections", %{mission: mission, target: target, port: port} do
      interface = build_interface(mission.id, port, [target.identifier])

      {:ok, server_pid} = TcpServerInterface.start_link(interface)

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

    test "handles client disconnections", %{mission: mission, target: target, port: port} do
      interface = build_interface(mission.id, port, [target.identifier])

      {:ok, server_pid} = TcpServerInterface.start_link(interface)

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

    test "receives and tracks data from clients", %{mission: mission, target: target, port: port} do
      interface = build_interface(mission.id, port, [target.identifier])

      {:ok, server_pid} = TcpServerInterface.start_link(interface)

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

    test "enforces max_clients limit", %{mission: mission, target: target, port: port} do
      # Set max clients to 2
      interface = build_interface(mission.id, port, [target.identifier], max_clients: 2)

      {:ok, server_pid} = TcpServerInterface.start_link(interface)

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
