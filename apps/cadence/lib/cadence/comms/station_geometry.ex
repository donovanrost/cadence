defmodule Cadence.Comms.StationGeometry do
  @moduledoc """
  Asks for a predicted-pass recompute when a station's geometry changes (#891): its location,
  its elevation mask, or whether it is active. The work is the `"station"` run of the durable
  `:pass_prediction` job (`Cadence.GroundNetworks.PredictedPasses`); Comms names it through the
  platform job queue because Comms may not depend on GroundNetworks.
  """

  alias Cadence.Ids
  alias Cadence.Jobs
  alias Cadence.Repo

  @geometry ~w(latitude_deg longitude_deg height_m elevation_mask_deg)

  @doc "Whether two `ground_station` documents differ in what pass prediction reads."
  @spec changed?(map() | nil, map() | nil) :: boolean()
  def changed?(previous, proposed), do: take(previous) != take(proposed)

  defp take(nil), do: %{}
  defp take(document), do: Map.take(document, @geometry)

  @doc """
  Stages the recompute in the current transaction (the dispatcher finds it once it commits), or
  enqueues it outside one. No ids, no job.
  """
  @spec stage_recompute(binary(), binary(), [binary()]) :: :ok
  def stage_recompute(_organization_id, _mission_id, []), do: :ok

  def stage_recompute(organization_id, mission_id, station_ids) do
    payload = %{
      "kind" => "station",
      "organization_id" => organization_id,
      "ground_station_ids" => Enum.uniq(station_ids)
    }

    run_id = Ids.new("pass_prediction_run")

    {:ok, _job} =
      if Repo.in_transaction?(),
        do: Jobs.enqueue_in_transaction(:pass_prediction, mission_id, run_id, payload),
        else: Jobs.enqueue(:pass_prediction, mission_id, run_id, payload)

    :ok
  end
end
