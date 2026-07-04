defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkerSupport do
  @moduledoc """
  Shared mechanical helpers for time-series marker projectors.
  """

  alias Cadence.Dashboards.{DataLink, Frame}
  alias CadenceWeb.OpsDashboardShowLive.WidgetLinks

  @spec event_links(Frame.t(), atom()) :: [DataLink.t()]
  def event_links(%Frame{} = frame, target) do
    frame
    |> WidgetLinks.data_links()
    |> Enum.filter(&(&1.target == target))
  end

  def event_links(_frame, _target), do: []

  @spec source_marker_context(map() | term()) :: map()
  def source_marker_context(meta) when is_map(meta) do
    request_context =
      meta
      |> context_value(:source_request_context)
      |> request_context_or_empty()

    direct_context =
      %{
        source_request_id: context_value(meta, :source_request_id),
        logical_source: context_value(meta, :logical_source),
        source_binding_id: context_value(meta, :source_binding_id),
        data_source_id: context_value(meta, :data_source_id),
        realm: context_value(meta, :realm),
        dataset: context_value(meta, :dataset),
        replay_run_id: context_value(meta, :replay_run_id)
      }
      |> drop_nil_values()

    Map.merge(request_context, direct_context)
  end

  def source_marker_context(_meta), do: %{}

  def request_context_or_empty(context) when is_map(context), do: context
  def request_context_or_empty(_context), do: %{}

  def timestamp_ms(%DateTime{} = value), do: DateTime.to_unix(value, :millisecond)
  def timestamp_ms(_value), do: nil

  def context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  def context_value(_context, _key), do: nil

  def field_values(fields, field_name) do
    case field_by_name(fields, field_name) do
      %{values: values} when is_list(values) -> values
      _missing -> []
    end
  end

  def field_by_name(fields, name), do: Enum.find(fields, &(&1.name == name))

  def data_link_id(%DataLink{} = link), do: link.link_id
  def data_link_id(_link), do: nil

  def data_link_target(%DataLink{} = link), do: marker_value_text(link.target)
  def data_link_target(_link), do: nil

  def data_link_target_id(%DataLink{} = link), do: link.target_id
  def data_link_target_id(_link), do: nil

  def context_text(value) when is_atom(value), do: Atom.to_string(value)
  def context_text(value), do: to_string(value)

  def marker_value_text(nil), do: nil
  def marker_value_text(value), do: context_text(value)

  def drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
