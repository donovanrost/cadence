defmodule Cadence.Spacecraft.ConfigKinds.ApidCompatibilityTest do
  use ExUnit.Case, async: true

  alias Cadence.Spacecraft.ConfigKinds.ApidCompatibility

  describe "sentences (ux U40 (d)/(e))" do
    test "wider, narrower, both, several" do
      assert ApidCompatibility.change_sentence("EARENDIL-312", %{from: [0x2A], to: [0x2A, 0x2B]}) ==
               "EARENDIL-312 will also decode APIDs 0x2B after this is applied (today only 0x2A)."

      assert ApidCompatibility.change_sentence("EARENDIL-312", %{
               from: [0x2A, 0x2B, 0x30],
               to: [0x2A]
             }) == "EARENDIL-312 will stop decoding APIDs 0x2B and 0x30 after this is applied."

      assert ApidCompatibility.change_sentence("EARENDIL-312", %{from: [0x2B], to: [0x31]}) ==
               "EARENDIL-312 will start decoding 0x31 and stop decoding 0x2B after this is applied."

      assert ApidCompatibility.changes_sentence(12) ==
               "12 spacecraft will decode different APIDs after this is applied."
    end

    test "at most five APIDs, then 'and N more'; strays per catalog" do
      assert ApidCompatibility.list(Enum.to_list(1..8)) ==
               "0x01, 0x02, 0x03, 0x04, 0x05 and 3 more"

      assert ApidCompatibility.stray_sentence([{"EARENDIL-312", [0x101, 0x1A0]}], "rev 15") ==
               "EARENDIL-312 handles APIDs 0x101 and 0x1A0, which rev 15 doesn't define. " <>
                 "Change its handled APIDs first."

      assert ApidCompatibility.stray_sentence([{"A", [0x101]}, {"B", [0x1A0]}], "rev 15") ==
               "2 spacecraft handle APIDs that rev 15 doesn't define (0x101 and 0x1A0). " <>
                 "Change their handled APIDs first."
    end
  end
end
