defmodule Cadence.Reads.MissionHealth do
  @moduledoc """
  Dashboard-oriented health summary built from the latest limit-state projection.
  """

  alias Cadence.Limits.Event
  alias Cadence.Reads.Limits, as: LimitReads

  @type normalized_state :: :red | :yellow | :green | :blue
  @type normalized_state_counts :: %{
          red: non_neg_integer(),
          yellow: non_neg_integer(),
          green: non_neg_integer(),
          blue: non_neg_integer()
        }
  @type scope_kind :: :mission | :spacecraft

  @type point_buckets :: %{
          red: [Event.t()],
          yellow: [Event.t()],
          green: [Event.t()],
          blue: [Event.t()]
        }

  @type scope_summary :: %{
          scope_id: binary(),
          scope_kind: scope_kind(),
          scope_label: binary(),
          spacecraft_id: binary() | nil,
          total_points: non_neg_integer(),
          violating_points: non_neg_integer(),
          normalized_state_counts: normalized_state_counts(),
          worst_normalized_state: normalized_state() | nil,
          updated_at: DateTime.t() | nil,
          point_buckets: point_buckets()
        }

  @type t :: %__MODULE__{
          mission_id: binary(),
          total_points: non_neg_integer(),
          violating_points: non_neg_integer(),
          normalized_state_counts: normalized_state_counts(),
          worst_normalized_state: normalized_state() | nil,
          updated_at: DateTime.t() | nil,
          point_buckets: point_buckets(),
          scope_summaries: [scope_summary()]
        }

  @empty_counts %{red: 0, yellow: 0, green: 0, blue: 0}
  @empty_point_buckets %{red: [], yellow: [], green: [], blue: []}

  defstruct [
    :mission_id,
    :worst_normalized_state,
    :updated_at,
    total_points: 0,
    violating_points: 0,
    normalized_state_counts: @empty_counts,
    point_buckets: @empty_point_buckets,
    scope_summaries: []
  ]

  @spec summary(binary(), keyword()) :: t()
  def summary(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    point_states = LimitReads.latest_states_for_mission(mission_id, opts)

    %__MODULE__{
      mission_id: mission_id,
      total_points: length(point_states),
      violating_points: count_violations(point_states),
      normalized_state_counts: count_normalized_states(point_states),
      worst_normalized_state: worst_normalized_state(point_states),
      updated_at: latest_receipt_time(point_states),
      point_buckets: bucket_point_states(point_states),
      scope_summaries: build_scope_summaries(mission_id, point_states)
    }
  end

  @spec summary(binary(), binary(), keyword()) :: t()
  def summary(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    point_states = LimitReads.latest_states_for_mission(organization_id, mission_id, opts)

    %__MODULE__{
      mission_id: mission_id,
      total_points: length(point_states),
      violating_points: count_violations(point_states),
      normalized_state_counts: count_normalized_states(point_states),
      worst_normalized_state: worst_normalized_state(point_states),
      updated_at: latest_receipt_time(point_states),
      point_buckets: bucket_point_states(point_states),
      scope_summaries: build_scope_summaries(mission_id, point_states)
    }
  end

  defp build_scope_summaries(mission_id, point_states) do
    point_states
    |> Enum.group_by(&scope_group_key/1)
    |> Enum.map(fn {{scope_kind, spacecraft_id}, scope_point_states} ->
      %{
        scope_id: scope_id(scope_kind, mission_id, spacecraft_id),
        scope_kind: scope_kind,
        scope_label: scope_label(scope_kind, mission_id, spacecraft_id),
        spacecraft_id: spacecraft_id,
        total_points: length(scope_point_states),
        violating_points: count_violations(scope_point_states),
        normalized_state_counts: count_normalized_states(scope_point_states),
        worst_normalized_state: worst_normalized_state(scope_point_states),
        updated_at: latest_receipt_time(scope_point_states),
        point_buckets: bucket_point_states(scope_point_states)
      }
    end)
    |> Enum.sort_by(&scope_sort_key/1)
  end

  defp count_violations(point_states) do
    Enum.count(point_states, & &1.violation)
  end

  defp count_normalized_states(point_states) do
    Enum.reduce(point_states, @empty_counts, fn point_state, counts ->
      Map.update!(counts, point_state.normalized_state, &(&1 + 1))
    end)
  end

  defp bucket_point_states(point_states) do
    point_states
    |> Enum.reduce(@empty_point_buckets, fn point_state, buckets ->
      Map.update!(buckets, point_state.normalized_state, &[point_state | &1])
    end)
    |> Map.new(fn {normalized_state, state_bucket} ->
      {normalized_state, Enum.sort_by(state_bucket, &point_sort_key/1)}
    end)
  end

  defp worst_normalized_state([]), do: nil

  defp worst_normalized_state(point_states) do
    point_states
    |> Enum.max_by(&normalized_state_severity/1)
    |> Map.fetch!(:normalized_state)
  end

  defp latest_receipt_time([]), do: nil

  defp latest_receipt_time(point_states) do
    point_states
    |> Enum.max_by(&DateTime.to_unix(&1.receipt_time, :microsecond))
    |> Map.fetch!(:receipt_time)
  end

  defp scope_group_key(%Event{spacecraft_id: nil}), do: {:mission, nil}
  defp scope_group_key(%Event{spacecraft_id: spacecraft_id}), do: {:spacecraft, spacecraft_id}

  defp scope_id(:mission, mission_id, nil), do: "mission:" <> mission_id
  defp scope_id(:spacecraft, _mission_id, spacecraft_id), do: "spacecraft:" <> spacecraft_id

  defp scope_label(:mission, mission_id, nil), do: mission_id
  defp scope_label(:spacecraft, _mission_id, spacecraft_id), do: spacecraft_id

  defp scope_sort_key(scope_summary) do
    {scope_kind_rank(scope_summary.scope_kind),
     normalized_state_rank(scope_summary.worst_normalized_state), scope_summary.scope_label}
  end

  defp point_sort_key(point_state) do
    {spacecraft_sort_key(point_state.spacecraft_id),
     normalized_state_rank(point_state.normalized_state), point_state.point_name}
  end

  defp spacecraft_sort_key(nil), do: ""
  defp spacecraft_sort_key(spacecraft_id), do: spacecraft_id

  defp scope_kind_rank(:mission), do: 0
  defp scope_kind_rank(:spacecraft), do: 1

  defp normalized_state_severity(%Event{normalized_state: normalized_state}),
    do: normalized_state_rank(normalized_state) * -1

  defp normalized_state_rank(:red), do: 0
  defp normalized_state_rank(:yellow), do: 1
  defp normalized_state_rank(:green), do: 2
  defp normalized_state_rank(:blue), do: 3
  defp normalized_state_rank(nil), do: 4
end
