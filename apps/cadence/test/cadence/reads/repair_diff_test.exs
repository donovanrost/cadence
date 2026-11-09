defmodule Cadence.Reads.RepairDiffTest do
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.ContactOpportunitySnapshot
  alias Cadence.Reads.RepairDiff

  defp pass(id, spacecraft, ref, minute) do
    at = DateTime.add(~U[2027-01-01 00:00:00Z], minute * 60)

    %ContactOpportunitySnapshot{
      contact_opportunity_snapshot_id: id,
      provider_opportunity_ref: ref,
      route_binding_document: %{"spacecraft_id" => spacecraft},
      normalized_opportunity_document: %{"ground_station_ref" => "SVB"},
      starts_at: at,
      ends_at: DateTime.add(at, 600)
    }
  end

  test "kept by provider ref, moved per spacecraft, the rest dropped or added" do
    before = [
      pass("a1", "sc-a", "w1", 0),
      pass("b1", "sc-b", "w2", 60),
      pass("c1", "sc-c", "w3", 90)
    ]

    after_passes = [
      pass("a2", "sc-a", "w1", 0),
      pass("b2", "sc-b", "w9", 75),
      pass("d2", "sc-d", "w4", 30)
    ]

    stations = %{"SVB" => %{id: "gs_svb", code: "SVB", name: "Svalbard B"}}
    diff = RepairDiff.diff(before, after_passes, stations)

    assert diff.totals == %{kept: 1, moved: 1, dropped: 1, added: 1}

    assert [%{snapshot_id: "a2", station: %{ref: "SVB", code: "SVB", name: "Svalbard B"}}] =
             diff.kept

    assert [
             %{
               spacecraft_id: "sc-b",
               from: %{snapshot_id: "b1"},
               to: %{snapshot_id: "b2"},
               offset_s: 900
             }
           ] = diff.moved

    assert [%{snapshot_id: "c1"}] = diff.dropped
    assert [%{snapshot_id: "d2"}] = diff.added
  end
end
