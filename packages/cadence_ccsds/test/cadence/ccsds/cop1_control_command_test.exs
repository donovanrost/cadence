defmodule Cadence.CCSDS.Transport.COP1.ControlCommandTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Transport.COP1.ControlCommand

  test "encodes and decodes the Unlock command" do
    assert {:ok, <<0>>} = ControlCommand.encode(:unlock)
    assert {:ok, :unlock} = ControlCommand.decode(<<0>>)
  end

  test "encodes and decodes the Set V(R) command" do
    assert {:ok, <<0x82, 0, 219>>} = ControlCommand.encode({:set_vr, 219})
    assert {:ok, {:set_vr, 219}} = ControlCommand.decode(<<0x82, 0, 219>>)
  end

  test "rejects reserved control-command encodings and invalid V(R) values" do
    assert {:error, {:invalid_control_command, <<1>>}} = ControlCommand.decode(<<1>>)

    assert {:error, {:invalid_receiver_frame_sequence_number, 256}} =
             ControlCommand.encode({:set_vr, 256})
  end
end
