defmodule Cadence.Runtime.Interfaces.FactoryTest do
  use Cadence.PureCase, async: true

  alias Cadence.Runtime.Interfaces.Factory
  alias Cadence.Runtime.Interfaces.TcpClientInterface
  alias Cadence.Runtime.Interfaces.TcpServerInterface
  alias Cadence.Transports.Interface

  describe "Factory with transport interfaces" do
    test "builds tcp_client child spec from transport interface" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-tcp-client",
        type: :tcp,
        endpoint: %{
          mode: "client",
          host: "192.168.1.100",
          port: 8080
        }
      }

      # Build child spec using Factory
      {module, entity} = Factory.child_spec_for(interface)

      # Verify module is correct
      assert module == TcpClientInterface

      # Verify entity is passed directly (no more config map)
      assert entity == interface
      assert entity.endpoint[:host] == "192.168.1.100"
      assert entity.endpoint[:port] == 8080
    end

    test "builds tcp_server child spec from transport interface" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-tcp-server",
        type: :tcp,
        endpoint: %{
          mode: "server",
          host: "0.0.0.0",
          port: 9000,
          max_clients: 50
        }
      }

      # Build child spec using Factory
      {module, entity} = Factory.child_spec_for(interface)

      # Verify module is correct
      assert module == TcpServerInterface

      # Verify entity is passed directly
      assert entity == interface
      assert entity.endpoint[:host] == "0.0.0.0"
      assert entity.endpoint[:port] == 9000
    end

    test "module_for_connection_type returns correct module for atoms" do
      assert Factory.module_for_connection_type(:tcp, %{mode: "client"}) == TcpClientInterface
      assert Factory.module_for_connection_type(:tcp, %{mode: "server"}) == TcpServerInterface
    end

    test "module_for_connection_type returns correct module for strings" do
      assert Factory.module_for_connection_type("tcp", %{"mode" => "client"}) ==
               TcpClientInterface

      assert Factory.module_for_connection_type("tcp", %{"mode" => "server"}) ==
               TcpServerInterface
    end

    test "connection_type_implemented? returns true for implemented types" do
      assert Factory.connection_type_implemented?(:tcp, %{mode: "client"}) == true
      assert Factory.connection_type_implemented?(:tcp, %{mode: "server"}) == true
      assert Factory.connection_type_implemented?("tcp", %{"mode" => "client"}) == true
      assert Factory.connection_type_implemented?("tcp", %{"mode" => "server"}) == true
    end

    test "connection_type_implemented? returns false for unimplemented types" do
      assert Factory.connection_type_implemented?(:udp, %{}) == false
      assert Factory.connection_type_implemented?(:serial, %{}) == false
      assert Factory.connection_type_implemented?("udp", %{"mode" => "server"}) == false
    end

    test "raises for unknown connection type" do
      interface = %Interface{
        id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        name: "test-unknown",
        type: :unknown_type
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
        type: :udp,
        endpoint: %{mode: "client"}
      }

      assert_raise RuntimeError, ~r/not yet implemented/, fn ->
        Factory.child_spec_for(interface)
      end
    end
  end
end
