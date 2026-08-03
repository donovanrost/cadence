defmodule CadenceWeb.OpsDashboardShowLive.MarkerCategories do
  @moduledoc """
  User-facing marker categories for the dashboard's Grafana-style
  annotation toggles.

  Hidden categories ride in the `hidden_markers` URL param as a sorted
  comma-separated list of category keys; an absent param means every
  category is visible. Event markers with an unknown `marker_type` stay
  visible (fail open).
  """

  # Plain limit-analysis markers can carry `marker_type: nil`, so the
  # "limits" category hides the whole limit-marker stream rather than
  # matching per-type.
  @categories [
    {"limits", "Limits",
     ["limit_analysis", "limit_analysis_bucket", "limit_definition_interval"]},
    {"contacts", "Contacts", ["contact_interval"]},
    {"source_status", "Source status", ["source_binding_interval", "source_health_transition"]},
    {"watermarks", "Watermarks & gaps",
     ["source_watermark_event", "source_watermark_cursor", "retention_gap"]},
    {"mission_events", "Mission events", ["mission_event"]},
    {"data_management", "Data management",
     ["telemetry_backfill_lifecycle", "telemetry_revision_range", "telemetry_revision_decision"]}
  ]

  @category_keys Enum.map(@categories, fn {key, _label, _types} -> key end)
  @category_by_marker_type Map.new(
                             for {key, _label, types} <- @categories, type <- types do
                               {type, key}
                             end
                           )

  @spec category_options() :: [{binary(), binary()}]
  def category_options do
    Enum.map(@categories, fn {key, label, _types} -> {label, key} end)
  end

  @spec category_keys() :: [binary()]
  def category_keys, do: @category_keys

  @doc """
  Normalizes the `hidden_markers` URL param (comma-separated string or
  list) or the Data-popover checkbox map (`%{"limits" => "false", ...}`,
  where `"false"` means hidden) into a sorted list of valid keys.
  """
  @spec normalize_param(term()) :: [binary()]
  def normalize_param(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> normalize_param()
  end

  def normalize_param(values) when is_list(values) do
    values
    |> Enum.filter(&(&1 in @category_keys))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def normalize_param(values) when is_map(values) do
    values
    |> Enum.filter(fn {_key, checked} -> checked in ["false", false] end)
    |> Enum.map(fn {key, _checked} -> key end)
    |> normalize_param()
  end

  def normalize_param(_value), do: []

  @spec to_param([binary()]) :: binary() | nil
  def to_param([]), do: nil
  def to_param(keys) when is_list(keys), do: keys |> normalize_param() |> Enum.join(",")

  @spec hidden?([binary()], binary()) :: boolean()
  def hidden?(hidden_categories, category_key), do: category_key in List.wrap(hidden_categories)

  @spec filter_limit_markers([map()], [binary()]) :: [map()]
  def filter_limit_markers(markers, hidden_categories) do
    if hidden?(hidden_categories, "limits"), do: [], else: markers
  end

  @spec filter_event_markers([map()], [binary()]) :: [map()]
  def filter_event_markers(markers, hidden_categories) do
    case List.wrap(hidden_categories) do
      [] -> markers
      hidden -> Enum.reject(markers, &hidden_marker?(&1, hidden))
    end
  end

  defp hidden_marker?(marker, hidden) do
    case Map.get(@category_by_marker_type, marker_type(marker)) do
      nil -> false
      category -> category in hidden
    end
  end

  defp marker_type(%{marker_type: type}), do: type
  defp marker_type(%{"marker_type" => type}), do: type
  defp marker_type(_marker), do: nil
end
