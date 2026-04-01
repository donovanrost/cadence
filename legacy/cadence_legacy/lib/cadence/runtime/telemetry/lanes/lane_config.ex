defmodule Cadence.Runtime.Telemetry.Lanes.LaneConfig do
  @moduledoc """
  Normalizes lane configuration for the lanes/shards telemetry pipeline.
  """

  @default_virtual_shard_multiplier 32

  @type t :: %{
          name: atom(),
          shard_count: pos_integer(),
          virtual_shards: pos_integer(),
          selectors: map(),
          priority: integer(),
          max_queue_depth: non_neg_integer() | nil,
          max_inflight: non_neg_integer() | nil
        }

  @spec from_opts(keyword()) :: [t()]
  def from_opts(opts) do
    lanes = Keyword.get(opts, :lanes) || Application.get_env(:cadence, :pipeline_lanes)
    shard_count = Keyword.get(opts, :shard_count, 8)
    normalize(lanes, shard_count)
  end

  @spec normalize(nil | list(), pos_integer()) :: [t()]
  def normalize(nil, shard_count) do
    [
      %{
        name: :payload,
        shard_count: shard_count,
        virtual_shards: default_virtual_shards(shard_count),
        selectors: %{}
      }
    ]
  end

  def normalize(lanes, shard_count) when is_list(lanes) do
    lanes
    |> Enum.map(&normalize_lane(&1, shard_count))
    |> Enum.uniq_by(& &1.name)
  end

  defp normalize_lane(lane, shard_count) when is_map(lane) do
    name = Map.fetch!(lane, :name)
    count = Map.get(lane, :shard_count, shard_count)
    selectors = Map.get(lane, :selectors, %{})

    %{
      name: name,
      shard_count: count,
      virtual_shards: Map.get(lane, :virtual_shards, default_virtual_shards(count)),
      selectors: selectors,
      priority: Map.get(lane, :priority, 0),
      max_queue_depth: Map.get(lane, :max_queue_depth),
      max_inflight: Map.get(lane, :max_inflight)
    }
  end

  defp normalize_lane(lane, shard_count) when is_list(lane) do
    lane
    |> Enum.into(%{})
    |> normalize_lane(shard_count)
  end

  defp default_virtual_shards(shard_count) do
    max(shard_count * @default_virtual_shard_multiplier, shard_count)
  end

  @spec lane_shard_count(nil | list(), atom(), pos_integer()) :: pos_integer()
  def lane_shard_count(lanes, lane_name, default_shard_count) do
    lanes = normalize(lanes, default_shard_count)
    lane = Enum.find(lanes, &lane_name_match?(&1.name, lane_name)) || List.first(lanes)
    (lane && lane.shard_count) || default_shard_count
  end

  defp lane_name_match?(name, lane_name) when is_atom(name) and is_atom(lane_name),
    do: name == lane_name

  defp lane_name_match?(name, lane_name) when is_binary(name) and is_binary(lane_name),
    do: name == lane_name

  defp lane_name_match?(name, lane_name) when is_atom(name) and is_binary(lane_name),
    do: Atom.to_string(name) == lane_name

  defp lane_name_match?(name, lane_name) when is_binary(name) and is_atom(lane_name),
    do: name == Atom.to_string(lane_name)

  defp lane_name_match?(_, _), do: false
end
