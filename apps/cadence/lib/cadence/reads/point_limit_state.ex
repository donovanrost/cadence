defmodule Cadence.Reads.PointLimitState do
  @moduledoc """
  A spacecraft's limit state per point, for the point reads (search, the live topic): from the
  runtime's latest alarm states and the compiled plan (#451 T3c; it read the ground limit states).

  A point's state is the worst of its parameter's policies: `:critical`, `:caution` or `:nominal`.
  A state is written when a parameter changes state, so a parameter the plan monitors on this
  spacecraft and that has none never left normal: `:nominal`. A parameter nothing monitors there
  has no state at all (`nil`). `catalog` is the mission's points (`PointCatalog.list_points/2`);
  a point the catalog does not map to a parameter is its own parameter.
  """

  alias Cadence.Reads.MonitoredParameters
  alias Cadence.SemanticObservations

  @type state :: :critical | :caution | :nominal

  @doc "`%{point_id => state}` for the points that have one, on `spacecraft_id`."
  @spec load(binary(), binary(), binary(), [map()], [binary()] | nil) :: %{binary() => state()}
  def load(organization_id, mission_id, spacecraft_id, catalog, point_ids \\ nil) do
    levels =
      SemanticObservations.levels_for_spacecraft(organization_id, mission_id, spacecraft_id)

    monitored =
      case MonitoredParameters.for_spacecraft(organization_id, mission_id, spacecraft_id) do
        {:ok, parameters} -> parameters
        :none -> MapSet.new()
      end

    wanted = point_ids && MapSet.new(point_ids)

    for point <- catalog,
        wanted == nil or MapSet.member?(wanted, point.point_id),
        parameter = point.parameter_id || point.point_id,
        state = state(Map.get(levels, parameter), MapSet.member?(monitored, parameter)),
        into: %{},
        do: {point.point_id, state}
  end

  defp state(nil, true), do: :nominal
  defp state(nil, false), do: nil
  defp state(level, _monitored), do: level
end
