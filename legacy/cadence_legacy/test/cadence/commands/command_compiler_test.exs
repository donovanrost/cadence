defmodule Cadence.Commands.CommandCompilerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Commands.CommandCompiler
  alias Cadence.MissionDatabase.{Argument, MetaCommand}
  alias Cadence.Test.Adapters.InMemoryCommandsRepository

  setup do
    cleanup = Cadence.TestSupport.enable_in_memory_adapters()
    InMemoryCommandsRepository.clear()
    on_exit(cleanup)
    :ok
  end

  test "fetch_command returns unknown_command when missing" do
    assert {:error, :unknown_command} =
             CommandCompiler.fetch_command("mission-1", "definition-1", "NOPE")
  end

  test "fetch_command returns command from repository when cache is unavailable" do
    definition_set_id = "definition-1"
    command = build_command("SET_MODE", 0x10, definition_set_id, [build_arg("mode", "uint")])

    {:ok, saved} = InMemoryCommandsRepository.save(command)

    assert {:ok, found} =
             CommandCompiler.fetch_command("mission-1", definition_set_id, "SET_MODE")

    assert found.id == saved.id
  end

  test "compile builds encoded payload and PDU" do
    command = build_command("SET_MODE", 0x10, "definition-1", [build_arg("mode", "uint")])
    target = %{id: "target-1", config: %{"command_apid" => 100}}

    assert {:ok, compiled} =
             CommandCompiler.compile(command, %{"mode" => 1}, target, "agg-1")

    assert compiled.encoded == <<0x00, 0x10, 0x01>>
    assert compiled.pdu.type == :space_packet
    assert compiled.pdu.value.apid == 100
    assert compiled.pdu.meta.command_aggregate_id == "agg-1"
    assert compiled.pdu.meta.command_name == "SET_MODE"
    assert compiled.pdu.meta.target_id == "target-1"
  end

  test "compile returns validation errors for missing arguments" do
    command =
      build_command("SET_MODE", 0x10, "definition-1", [
        build_arg("mode", "uint", required: true)
      ])

    target = %{id: "target-1", config: %{"command_apid" => 100}}

    assert {:error, :validation_failed, errors} =
             CommandCompiler.compile(command, %{}, target, "agg-1")

    assert {"mode", "is required"} in errors
  end

  test "compile returns missing_command_apid when target is not configured" do
    command = build_command("SET_MODE", 0x10, "definition-1", [build_arg("mode", "uint")])
    target = %{id: "target-1", config: %{}}

    assert {:error, :missing_command_apid} =
             CommandCompiler.compile(command, %{"mode" => 1}, target, "agg-1")
  end

  defp build_command(name, opcode, definition_set_id, arguments) do
    %MetaCommand{
      id: Ecto.UUID.generate(),
      name: name,
      opcode: opcode,
      definition_set_id: definition_set_id,
      arguments: arguments,
      allowed_phases: []
    }
  end

  defp build_arg(name, data_type_ref, opts \\ []) do
    %Argument{
      name: name,
      data_type_ref: data_type_ref,
      bit_offset: Keyword.get(opts, :bit_offset, 0),
      bit_length: Keyword.get(opts, :bit_length, 8),
      required: Keyword.get(opts, :required, false),
      default_value: Keyword.get(opts, :default_value)
    }
  end
end
