defmodule Cadence.Comms.StationGeometry do
  @moduledoc """
  Asks for a predicted-pass recompute when a station's geometry changes (#891): its location,
  its elevation mask, or whether it is active. The work is the `"station"` run of the durable
  `:pass_prediction` job (`Cadence.GroundNetworks.PredictedPasses`), staged through
  `Cadence.Platform.PassPredictionJobs` because Comms may not depend on GroundNetworks.
  """

  alias Cadence.Platform.PassPredictionJobs

  @geometry ~w(latitude_deg longitude_deg height_m elevation_mask_deg)

  @doc "Whether two `ground_station` documents differ in what pass prediction reads."
  @spec changed?(map() | nil, map() | nil) :: boolean()
  def changed?(previous, proposed), do: take(previous) != take(proposed)

  defp take(nil), do: %{}
  defp take(document), do: Map.take(document, @geometry)

  @doc "Stages the recompute of these stations (`Cadence.Platform.PassPredictionJobs`)."
  @spec stage_recompute(binary(), binary(), [binary()]) :: :ok
  def stage_recompute(organization_id, mission_id, station_ids) do
    {:ok, _job} = PassPredictionJobs.stage_stations(organization_id, mission_id, station_ids)
    :ok
  end
end
