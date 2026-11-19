defmodule Cadence.Reads.PassIncompleteAtEndTest do
  @moduledoc "ux U67: the cut-off bytes at a pass's end, summed per kind from the settlement."
  use ExUnit.Case, async: true

  alias Cadence.Reads.PassIncompleteAtEnd

  defp metadata(entries), do: %{"settlement" => %{"incomplete_at_end" => entries}}

  test "sums the paths' frame and packet bytes; nil when nothing was cut off or unknown" do
    assert PassIncompleteAtEnd.from_metadata(
             metadata([
               %{
                 "path_id" => "a",
                 "frame_bytes" => 6,
                 "packet_octets" => 0,
                 "journal_bytes" => 6
               },
               %{
                 "path_id" => "b",
                 "frame_bytes" => 31,
                 "packet_octets" => 12,
                 "journal_bytes" => 43
               }
             ])
           ) == %{frame_bytes: 37, packet_bytes: 12}

    assert PassIncompleteAtEnd.from_metadata(
             metadata([%{"frame_bytes" => 0, "packet_octets" => 5, "journal_bytes" => 5}])
           ) == %{frame_bytes: 0, packet_bytes: 5}

    assert PassIncompleteAtEnd.from_metadata(metadata([])) == nil
    assert PassIncompleteAtEnd.from_metadata(%{"settlement" => %{}}) == nil
    assert PassIncompleteAtEnd.from_metadata(%{}) == nil
    assert PassIncompleteAtEnd.from_metadata(nil) == nil
  end
end
