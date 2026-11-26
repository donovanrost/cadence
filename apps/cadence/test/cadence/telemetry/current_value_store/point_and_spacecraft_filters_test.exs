defmodule Cadence.Telemetry.CurrentValueStore.PointAndSpacecraftFiltersTest do
  @moduledoc """
  `latest_values_for_mission` restricted to `point_ids:` and `spacecraft_ids:` (#794): the read
  of a few points on many spacecraft holds only those values, in both backends.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.CurrentValueStore.{ETS, Postgres}
  alias Cadence.Telemetry.Sample

  @mission "mission-latest-filters"

  defp samples do
    for craft <- 1..1_200, point <- ["HK.a", "HK.b", "HK.c"] do
      %Sample{
        sample_id: "s-#{craft}-#{point}",
        mission_id: @mission,
        spacecraft_id: "sc-#{craft}",
        point_id: point,
        point_name: point,
        packet_definition_id: "pd-1",
        packet_definition_version: 1,
        packet_id: "p-#{craft}",
        evidence_id: "e-#{craft}",
        raw_value: craft,
        engineering_value: craft,
        quality_state: :good,
        generation_time: ~U[2026-11-26 12:00:00Z],
        receipt_time: ~U[2026-11-26 12:00:01Z],
        provenance: %{}
      }
    end
  end

  defp assert_filters(read) do
    crafts = for n <- 1..1_100, do: "sc-#{n}"

    values = read.(point_ids: ["HK.a", "HK.c"], spacecraft_ids: crafts)
    assert length(values) == 2_200
    assert values |> Enum.map(& &1.point_id) |> Enum.uniq() |> Enum.sort() == ["HK.a", "HK.c"]
    assert values |> Enum.map(& &1.spacecraft_id) |> Enum.uniq() |> length() == 1_100
    refute Enum.any?(values, &(&1.spacecraft_id in ["sc-1101", "sc-1200"]))

    assert [%{spacecraft_id: "sc-7", point_id: "HK.b"}] =
             read.(point_ids: ["HK.b"], spacecraft_ids: ["sc-7", "ghost"])

    assert read.(point_ids: ["HK.nothing"], spacecraft_ids: crafts) == []
    assert read.(point_ids: ["HK.a"], spacecraft_ids: []) == []

    # Either filter alone, and neither (the whole mission).
    assert length(read.(point_ids: ["HK.a"])) == 1_200
    assert length(read.(spacecraft_ids: ["sc-1", "sc-2"])) == 6
    assert length(read.([])) == 3_600
  end

  test "the Postgres store reads only the asked points and spacecraft, in chunks" do
    # The rows are the subject, not the packets they point at (the test transaction rolls back).
    Repo.query!("SET LOCAL session_replication_role = replica")

    for chunk <- Enum.chunk_every(samples(), 500),
        do: assert(:ok = Postgres.record_samples(chunk))

    assert_filters(&Postgres.latest_values_for_mission(@mission, &1))
  end

  test "the ETS store reads only the asked points and spacecraft" do
    table = :"latest_filters_#{System.unique_integer([:positive])}"
    start_supervised!({ETS, name: table, table_name: table})
    backend_opts = [table_name: table]

    assert :ok = ETS.record_samples(samples(), backend_opts)
    assert_filters(&ETS.latest_values_for_mission(@mission, &1, backend_opts))
  end
end
