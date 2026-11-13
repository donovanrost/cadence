defmodule Cadence.Reads.ProfileDirectoryTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.ProfileDirectory
  alias Cadence.SpacecraftType

  test "counts pinned spacecraft and those on older versions" do
    profile = %SpacecraftType{
      spacecraft_type_id: "p",
      display_name: "Block 1",
      version: 4,
      downlink_protocol: :tm,
      uplink_protocol: :tc,
      packet_protocol: :space_packet
    }

    [row] =
      ProfileDirectory.build([profile], [
        %{spacecraft_type_id: "p", spacecraft_type_version: 4, count: 497},
        %{spacecraft_type_id: "p", spacecraft_type_version: 3, count: 3},
        %{spacecraft_type_id: "other", spacecraft_type_version: 1, count: 9}
      ])

    assert row.spacecraft_count == 500
    assert row.spacecraft_on_older_versions == 3
    assert row.downlink_protocol == %{value: "tm", label: "CCSDS TM"}
    assert row.uplink_protocol == %{value: "tc", label: "CCSDS TC"}
  end

  test "override_count and last_change read like the detail's" do
    profile = %SpacecraftType{spacecraft_type_id: "p", display_name: "Block 1", version: 3}
    at = ~U[2026-11-12 10:00:00.000000Z]

    assert [%{override_count: 7, last_change: %{version: 3, revision: nil, at: ^at, actor: nil}}] =
             ProfileDirectory.build([profile], [], %{}, %{
               override_counts: %{"p" => 7, "other" => 2},
               version_times: %{{"p", 3} => at, {"p", 2} => ~U[2026-11-01 00:00:00Z]}
             })

    # Without them: none counted, no last change known.
    assert [%{override_count: 0, last_change: nil}] = ProfileDirectory.build([profile], [])
  end

  test "a profile nobody pins has zero counts" do
    profile = %SpacecraftType{spacecraft_type_id: "p", display_name: "Spare", version: 1}

    assert [%{spacecraft_count: 0, spacecraft_on_older_versions: 0}] =
             ProfileDirectory.build([profile], [])
  end
end
