defmodule Cadence.Interfaces.FactoryTest do
  use Cadence.DataCase, async: false

  alias Cadence.Interfaces
  alias Cadence.Interfaces.Factory
  alias Cadence.TestHelpers

  describe "Factory with target associations" do
    test "builds tcp_client config with associated targets" do
      # Setup mission and targets
      setup_result = TestHelpers.full_test_setup()
      mission = setup_result.mission
      target = hd(setup_result.targets)

      # Create a TCP client interface
      {:ok, interface} =
        Interfaces.create_interface(%{
          mission_id: mission.id,
          name: "test-tcp-client",
          connection_type: "tcp_client",
          host: "192.168.1.100",
          port: 8080
        })

      # Associate target with interface
      {:ok, _assoc} = Interfaces.add_target_to_interface(target, interface, "read")

      # Build child spec using Factory
      {module, opts} = Factory.child_spec_for(interface)

      # Verify module is correct
      assert module == Cadence.Interfaces.TcpClientInterface

      # Verify config has target_id from association
      config = Keyword.get(opts, :config)
      assert config.target_id == target.identifier
      assert config.host == "192.168.1.100"
      assert config.port == 8080
    end

    test "builds tcp_server config with associated targets" do
      # Setup mission and targets
      setup_result = TestHelpers.full_test_setup()
      mission = setup_result.mission
      targets = setup_result.targets

      # Create a TCP server interface
      {:ok, interface} =
        Interfaces.create_interface(%{
          mission_id: mission.id,
          name: "test-tcp-server",
          connection_type: "tcp_server",
          bind_address: "0.0.0.0",
          bind_port: 9000
        })

      # Associate multiple targets with interface
      Enum.each(targets, fn target ->
        {:ok, _assoc} = Interfaces.add_target_to_interface(target, interface, "read")
      end)

      # Build child spec using Factory
      {module, opts} = Factory.child_spec_for(interface)

      # Verify module is correct
      assert module == Cadence.Interfaces.TcpServerInterface

      # Verify config has target_ids from associations
      config = Keyword.get(opts, :config)
      assert is_list(config.target_ids)
      assert length(config.target_ids) == 3

      # Verify all target identifiers are present
      target_identifiers = Enum.map(targets, & &1.identifier)
      assert Enum.all?(target_identifiers, fn id -> id in config.target_ids end)

      assert config.bind_address == "0.0.0.0"
      assert config.bind_port == 9000
    end

    test "builds tcp_client config with unknown when no targets associated" do
      # Setup mission
      setup_result = TestHelpers.full_test_setup()
      mission = setup_result.mission

      # Create a TCP client interface without associating targets
      {:ok, interface} =
        Interfaces.create_interface(%{
          mission_id: mission.id,
          name: "test-tcp-client-no-targets",
          connection_type: "tcp_client",
          host: "localhost",
          port: 8081
        })

      # Build child spec using Factory
      {_module, opts} = Factory.child_spec_for(interface)

      # Verify config uses "unknown" as fallback
      config = Keyword.get(opts, :config)
      assert config.target_id == "unknown"
    end

    test "builds tcp_server config with unknown when no targets associated" do
      # Setup mission
      setup_result = TestHelpers.full_test_setup()
      mission = setup_result.mission

      # Create a TCP server interface without associating targets
      {:ok, interface} =
        Interfaces.create_interface(%{
          mission_id: mission.id,
          name: "test-tcp-server-no-targets",
          connection_type: "tcp_server",
          bind_address: "127.0.0.1",
          bind_port: 9001
        })

      # Build child spec using Factory
      {_module, opts} = Factory.child_spec_for(interface)

      # Verify config uses ["unknown"] as fallback
      config = Keyword.get(opts, :config)
      assert config.target_ids == ["unknown"]
    end
  end
end
