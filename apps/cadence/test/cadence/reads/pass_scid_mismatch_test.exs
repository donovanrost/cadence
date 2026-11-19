defmodule Cadence.Reads.PassScidMismatchTest do
  @moduledoc "ux U81 §2 (#102): a pass's frames refused for another SCID, per path, from the settlement."
  use ExUnit.Case, async: true

  alias Cadence.Reads.PassScidMismatch

  @index %{"FBK" => %{id: "ground_station_fbk", code: "FBK", name: "Fairbanks"}}

  defp metadata(entries), do: %{"settlement" => %{"scid_mismatch" => entries}}
  defp read(metadata), do: PassScidMismatch.from_metadata(metadata, fn -> @index end)

  defp entry(overrides),
    do:
      Map.merge(
        %{
          "path_id" => "path-a",
          "provider_binding_id" => "pb-a",
          "ground_station_ref" => "FBK",
          "expected_scid" => 1,
          "frames" => 412,
          "frames_total" => 430,
          "scids" => [3],
          "scid_count" => 1,
          "spacecraft_id" => "spacecraft-earendil-312"
        },
        overrides
      )

  test "one path per refusing entry, most frames first, the station resolved like pass rows" do
    assert %{
             expected_scid: 1,
             paths: [
               %{
                 station: %{ref: "FBK", id: "ground_station_fbk", code: "FBK", name: "Fairbanks"},
                 frames: 412,
                 scids: [3],
                 scid_count: 1,
                 path_id: "path-a",
                 provider_binding_id: "pb-a"
               },
               %{station: nil, frames: 8, scids: [3, 7], scid_count: 2, path_id: "path-b"}
             ]
           } =
             read(
               metadata([
                 entry(%{
                   "path_id" => "path-b",
                   "frames" => 8,
                   "scids" => [7, 3],
                   "scid_count" => 2,
                   "ground_station_ref" => nil
                 }),
                 entry(%{})
               ])
             )
  end

  test "a clean path (frames 0, kept so domain can count 'most') isn't listed" do
    assert %{paths: [%{path_id: "path-a"}]} =
             read(metadata([entry(%{}), entry(%{"path_id" => "path-b", "frames" => 0})]))
  end

  test "scids stay sorted and capped at 8; scid_count keeps domain's uncapped count" do
    many = Enum.to_list(20..9//-1)

    assert %{paths: [%{scids: [9, 10, 11, 12, 13, 14, 15, 16], scid_count: 12}]} =
             read(metadata([entry(%{"scids" => many, "scid_count" => 12})]))
  end

  test "nil when nothing was refused, unsettled or from before #102; never an empty list" do
    assert read(metadata([entry(%{"frames" => 0})])) == nil
    assert read(metadata([])) == nil
    assert read(%{"settlement" => %{}}) == nil
    assert read(%{}) == nil
    assert read(nil) == nil
  end

  test "the station index is only read when there is something to show" do
    assert PassScidMismatch.from_metadata(%{}, fn -> flunk("index read") end) == nil
  end
end
