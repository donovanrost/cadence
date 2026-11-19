defmodule Cadence.ContactPlanning.StationConflictsTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.{GroundStation, StationRefs}
  alias Cadence.ContactPlanning.StationConflicts

  @t ~U[2027-01-01 00:00:00Z]

  defp pass(id, ref, from_s, to_s),
    do: %{
      contact_opportunity_snapshot_id: id,
      normalized_opportunity_document: %{"ground_station_ref" => ref},
      starts_at: DateTime.add(@t, from_s),
      ends_at: DateTime.add(@t, to_s)
    }

  test "outage and maintenance block; degraded only warns; other stations and times are clear" do
    index =
      StationRefs.build([
        %GroundStation{
          ground_station_id: "gs_fai",
          code: "FAI",
          display_name: "Fairbanks",
          metadata: %{}
        },
        %GroundStation{
          ground_station_id: "gs_sva",
          code: "SVA",
          display_name: "Svalbard",
          metadata: %{}
        }
      ])

    windows = %{
      "gs_fai" => [
        %{window_id: "w_out", kind: :outage, starts_at: DateTime.add(@t, 0), ends_at: nil}
      ],
      "gs_sva" => [
        %{
          window_id: "w_deg",
          kind: :degraded,
          starts_at: DateTime.add(@t, 1_000),
          ends_at: DateTime.add(@t, 2_000)
        }
      ]
    }

    passes = [
      pass("p1", "FAI", 100, 500),
      pass("p2", "FAI", 600, 900),
      pass("p3", "SVA", 1_500, 1_800),
      pass("p4", "SVA", 3_000, 3_500),
      pass("p5", "unknown-ref", 100, 500)
    ]

    assert %{conflicts: [conflict], at_risk: [risk]} =
             StationConflicts.evaluate(passes, index, windows)

    assert conflict == %{
             code: "station_unavailable",
             ground_station_id: "gs_fai",
             window_id: "w_out",
             kind: :outage,
             snapshot_ids: ["p1", "p2"]
           }

    assert %{code: "station_degraded", snapshot_ids: ["p3"], window_id: "w_deg"} = risk
  end
end
