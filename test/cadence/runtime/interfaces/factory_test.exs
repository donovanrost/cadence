defmodule Cadence.Runtime.Interfaces.FactoryTest do
  use Cadence.DataCase, async: false

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.Factory
  alias Cadence.Runtime.Interfaces.TcpClientInterface
  alias Cadence.Runtime.Interfaces.TcpServerInterface

  describe "Factory with domain entities" do
    test "builds tcp_client child spec from domain entity" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-tcp-client",
        connection_type: :tcp_client,
        host: "192.168.1.100",
        port: 8080,
        target_ids: ["SAT-1"],
        protocols: []
      }

      # Build child spec using Factory
      {module, entity} = Factory.child_spec_for(interface)

      # Verify module is correct
      assert module == TcpClientInterface

      # Verify entity is passed directly (no more config map)
      assert entity == interface
      assert entity.target_ids == ["SAT-1"]
      assert entity.host == "192.168.1.100"
      assert entity.port == 8080
    end

    test "builds tcp_server child spec from domain entity" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-tcp-server",
        connection_type: :tcp_server,
        bind_address: "0.0.0.0",
        bind_port: 9000,
        target_ids: ["SAT-1", "SAT-2", "SAT-3"],
        config: %{max_clients: 50},
        protocols: []
      }

      # Build child spec using Factory
      {module, entity} = Factory.child_spec_for(interface)

      # Verify module is correct
      assert module == TcpServerInterface

      # Verify entity is passed directly
      assert entity == interface
      assert length(entity.target_ids) == 3
      assert entity.bind_address == "0.0.0.0"
      assert entity.bind_port == 9000
    end

    test "module_for_connection_type returns correct module for atoms" do
      assert Factory.module_for_connection_type(:tcp_client) == TcpClientInterface
      assert Factory.module_for_connection_type(:tcp_server) == TcpServerInterface
    end

    test "module_for_connection_type returns correct module for strings" do
      assert Factory.module_for_connection_type("tcp_client") == TcpClientInterface
      assert Factory.module_for_connection_type("tcp_server") == TcpServerInterface
    end

    test "connection_type_implemented? returns true for implemented types" do
      assert Factory.connection_type_implemented?(:tcp_client) == true
      assert Factory.connection_type_implemented?(:tcp_server) == true
      assert Factory.connection_type_implemented?("tcp_client") == true
      assert Factory.connection_type_implemented?("tcp_server") == true
    end

    test "connection_type_implemented? returns false for unimplemented types" do
      assert Factory.connection_type_implemented?(:udp_client) == false
      assert Factory.connection_type_implemented?(:serial) == false
      assert Factory.connection_type_implemented?("udp_server") == false
    end

    test "raises for unknown connection type" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-unknown",
        connection_type: :unknown_type,
        protocols: []
      }

      assert_raise ArgumentError, ~r/Unknown connection_type/, fn ->
        Factory.child_spec_for(interface)
      end
    end

    test "raises for unimplemented connection type" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-udp",
        connection_type: :udp_client,
        protocols: []
      }

      assert_raise RuntimeError, ~r/not yet implemented/, fn ->
        Factory.child_spec_for(interface)
      end
    end
  end
end
