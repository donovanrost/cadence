defmodule CadenceWeb.Console.PredictedPassJSON do
  @moduledoc "The predicted-pass page (#891): rows with names and SCIDs, cursor and coverage."

  alias Cadence.GroundNetworks.PredictedPass

  def page(page) do
    %{
      data: Enum.map(page.passes, &pass(&1, page)),
      meta: %{next_cursor: page.next_cursor, coverage: coverage(page.coverage)}
    }
  end

  defp pass(%PredictedPass{} = pass, page) do
    spacecraft = Map.get(page.spacecraft, pass.spacecraft_id)
    station = Map.get(page.stations, pass.ground_station_id)

    %{
      id: pass.predicted_pass_id,
      aos: time(pass.aos),
      tca: time(pass.tca),
      los: time(pass.los),
      max_elevation_deg: pass.max_elevation_deg,
      aos_azimuth_deg: pass.aos_azimuth_deg,
      los_azimuth_deg: pass.los_azimuth_deg,
      spacecraft: %{
        id: pass.spacecraft_id,
        name: spacecraft && spacecraft.display_name,
        scid: spacecraft && spacecraft.scid
      },
      station: %{
        id: pass.ground_station_id,
        display_name: station && station.display_name,
        code: station && station.code
      },
      element_set: %{
        id: pass.element_set_id,
        epoch: time(Map.get(page.element_set_epochs, pass.element_set_id))
      },
      computed_at: time(pass.computed_at)
    }
  end

  defp coverage(coverage) do
    %{
      horizon_end: time(coverage.horizon_end),
      computed_at: time(coverage.computed_at),
      unpredicted: coverage.unpredicted
    }
  end

  defp time(nil), do: nil
  defp time(%DateTime{} = time), do: DateTime.to_iso8601(time)
end
