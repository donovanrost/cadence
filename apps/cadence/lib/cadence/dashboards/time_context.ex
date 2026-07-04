defmodule Cadence.Dashboards.TimeContext do
  @moduledoc """
  Dashboard runtime time context.

  The engine accepts maps at the boundary, then normalizes them into this struct
  before planning source requests.
  """

  @type t :: %__MODULE__{
          mode: atom() | binary() | nil,
          axis: atom() | binary() | nil,
          from: DateTime.t() | binary() | nil,
          to: DateTime.t() | binary() | nil,
          range: map() | nil,
          start: DateTime.t() | binary() | nil,
          end: DateTime.t() | binary() | nil,
          start_time: DateTime.t() | binary() | nil,
          end_time: DateTime.t() | binary() | nil,
          refresh_ms: non_neg_integer() | nil,
          replay_run_id: binary() | nil,
          window_seconds: pos_integer() | nil
        }

  defstruct [
    :mode,
    :axis,
    :from,
    :to,
    :range,
    :start,
    :end,
    :start_time,
    :end_time,
    :refresh_ms,
    :replay_run_id,
    :window_seconds
  ]

  @valid_modes [
    nil,
    :live,
    "live",
    :range,
    "range",
    :archive,
    "archive",
    :replay_run,
    "replay_run"
  ]
  @valid_axes [nil, :generation_time, "generation_time", :receipt_time, "receipt_time"]
  @known_keys [
    :mode,
    :axis,
    :from,
    :to,
    :range,
    :start,
    :end,
    :start_time,
    :end_time,
    :refresh_ms,
    :replay_run_id,
    :window_seconds
  ]

  @spec resolve(map() | t() | nil, map() | t() | nil, map() | t() | nil) :: t()
  def resolve(runtime_context, default_context, override_context) do
    default_context
    |> merge(runtime_context)
    |> merge(override_context)
    |> from_map()
  end

  @spec from_map(map() | t() | nil) :: t()
  def from_map(%__MODULE__{} = context), do: context
  def from_map(nil), do: %__MODULE__{}

  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      mode: get_attr(attrs, :mode),
      axis: get_attr(attrs, :axis),
      from: get_attr(attrs, :from),
      to: get_attr(attrs, :to),
      range: normalize_range(get_attr(attrs, :range)),
      start: get_attr(attrs, :start),
      end: get_attr(attrs, :end),
      start_time: get_attr(attrs, :start_time),
      end_time: get_attr(attrs, :end_time),
      refresh_ms: get_attr(attrs, :refresh_ms),
      replay_run_id: get_attr(attrs, :replay_run_id),
      window_seconds: get_attr(attrs, :window_seconds)
    }
  end

  @spec validate(t()) :: [atom()]
  def validate(%__MODULE__{} = context) do
    []
    |> maybe_add(context.mode not in @valid_modes, :unsupported_time_mode)
    |> maybe_add(context.axis not in @valid_axes, :unsupported_time_axis)
  end

  defp merge(left, nil), do: to_known_map(left)
  defp merge(left, right), do: Map.merge(to_known_map(left), to_known_map(right))

  defp to_known_map(%__MODULE__{} = context),
    do: context |> Map.from_struct() |> drop_nil_values()

  defp to_known_map(nil), do: %{}

  defp to_known_map(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_key(key) do
        nil -> acc
        normalized_key -> maybe_put(acc, normalized_key, value)
      end
    end)
  end

  defp normalize_key(key) when key in @known_keys, do: key
  defp normalize_key(key) when is_binary(key), do: normalize_string_key(key)
  defp normalize_key(_key), do: nil

  defp normalize_string_key("mode"), do: :mode
  defp normalize_string_key("axis"), do: :axis
  defp normalize_string_key("from"), do: :from
  defp normalize_string_key("to"), do: :to
  defp normalize_string_key("range"), do: :range
  defp normalize_string_key("start"), do: :start
  defp normalize_string_key("end"), do: :end
  defp normalize_string_key("start_time"), do: :start_time
  defp normalize_string_key("end_time"), do: :end_time
  defp normalize_string_key("refresh_ms"), do: :refresh_ms
  defp normalize_string_key("replay_run_id"), do: :replay_run_id
  defp normalize_string_key("window_seconds"), do: :window_seconds
  defp normalize_string_key(_key), do: nil

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp normalize_range(nil), do: nil

  defp normalize_range(range) when is_map(range) do
    Map.new(range, fn {key, value} -> {normalize_range_key(key), value} end)
  end

  defp normalize_range_key(key) when is_atom(key), do: key

  defp normalize_range_key(key) when is_binary(key) do
    Map.get(%{"kind" => :kind, "duration_ms" => :duration_ms}, key, key)
  end

  defp maybe_put(acc, _key, nil), do: acc
  defp maybe_put(acc, key, value), do: Map.put(acc, key, value)

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_add(errors, false, _error), do: errors
  defp maybe_add(errors, true, error), do: errors ++ [error]
end
