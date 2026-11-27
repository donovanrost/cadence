defmodule CadenceWeb.Console.PredictedPassJSONTest do
  @moduledoc """
  The predicted-pass page never sends a row with a null spacecraft name, SCID or element-set
  epoch (#891): a row whose lookups miss (its spacecraft was deleted mid-read) is dropped.
  """
  use ExUnit.Case, async: true

  alias Cadence.GroundNetworks.PredictedPass
  alias CadenceWeb.Console.PredictedPassJSON

  @at ~U[2026-11-28 12:00:00.000000Z]

  test "drops a row whose spacecraft or element set no longer resolves, keeping the cursor" do
    page = %{
      passes: [
        pass("pass-1", "craft-1", "elset-1"),
        pass("pass-2", "craft-gone", "elset-2"),
        pass("pass-3", "craft-1", "elset-gone")
      ],
      spacecraft: %{"craft-1" => %{display_name: "Earendil 1", scid: 101}},
      stations: %{"station-1" => %{display_name: "Svalbard", code: "SVB"}},
      element_set_epochs: %{"elset-1" => @at, "elset-2" => @at},
      next_cursor: "cursor-after-pass-3",
      coverage: %{horizon_end: @at, computed_at: @at, unpredicted: %{}}
    }

    assert %{data: [row], meta: %{next_cursor: "cursor-after-pass-3"}} =
             PredictedPassJSON.page(page)

    assert %{id: "pass-1", spacecraft: %{name: "Earendil 1", scid: 101}} = row
    assert row.element_set.epoch == "2026-11-28T12:00:00.000000Z"
  end

  defp pass(id, spacecraft_id, element_set_id) do
    %PredictedPass{
      predicted_pass_id: id,
      mission_id: "mission-1",
      spacecraft_id: spacecraft_id,
      ground_station_id: "station-1",
      element_set_id: element_set_id,
      aos: @at,
      tca: @at,
      los: @at,
      max_elevation_deg: 42.0,
      aos_azimuth_deg: 10.0,
      los_azimuth_deg: 200.0,
      computed_at: @at
    }
  end
end
