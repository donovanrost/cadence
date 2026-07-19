defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusResources do
  @moduledoc """
  Operational-resource fallback and row presentation for focused sources.
  """

  @type href_fun :: (atom(), term() -> binary() | nil)

  @spec default() :: map()
  def default do
    %{
      transport: nil,
      source_endpoint: nil,
      link_assignment: nil,
      routing_rule: nil,
      ground_station: nil
    }
  end

  @spec put_inferred_ground_station(map(), binary() | nil) :: map()
  def put_inferred_ground_station(resources, ground_station_id) when is_map(resources) do
    %{
      resources
      | ground_station:
          resources.ground_station || inferred_ground_station(ground_station_id, resources)
    }
  end

  @spec build(map(), map(), href_fun()) :: map() | nil
  def build(focus, resources, href_fun)
      when is_map(focus) and is_map(resources) and is_function(href_fun, 2) do
    rows =
      [
        resource_row(resources, href_fun, :selected_target, "target", focus.selected_target),
        resource_row(resources, href_fun, :selected_id, "selected", focus.selected_id),
        resource_row(resources, href_fun, :transport_id, "transport", focus.transport_id),
        resource_row(
          resources,
          href_fun,
          :source_endpoint_id,
          "endpoint",
          focus.source_endpoint_id
        ),
        resource_row(
          resources,
          href_fun,
          :ground_station_id,
          "station",
          focus.ground_station_id
        ),
        resource_row(resources, href_fun, :link_id, "link", focus.link_id)
      ]
      |> Enum.reject(&is_nil/1)

    if rows == [] do
      nil
    else
      %{
        selected_target: focus.selected_target,
        selected_id: focus.selected_id,
        transport_id: focus.transport_id,
        source_endpoint_id: focus.source_endpoint_id,
        ground_station_id: focus.ground_station_id,
        link_id: focus.link_id,
        rows: rows
      }
    end
  end

  defp inferred_ground_station(nil, _resources), do: nil

  defp inferred_ground_station(ground_station_id, resources) do
    source_label =
      [
        ground_station_source(resources.source_endpoint, ground_station_id),
        ground_station_source(resources.transport, ground_station_id),
        ground_station_source(resources.link_assignment, ground_station_id)
      ]
      |> Enum.find(&is_binary/1)

    %{
      id: ground_station_id,
      label: ground_station_label(ground_station_id, source_label),
      status: if(source_label, do: :inferred, else: :unverified)
    }
  end

  defp ground_station_source(nil, _ground_station_id), do: nil

  defp ground_station_source(resource, ground_station_id) do
    metadata = resource_value(resource, :metadata) || %{}
    configuration = resource_value(resource, :configuration) || %{}

    candidate =
      metadata_value(metadata, "ground_station_id") ||
        metadata_value(metadata, "antenna_id") ||
        metadata_value(configuration, "ground_station_id") ||
        metadata_value(configuration, "antenna_id")

    if candidate == ground_station_id do
      resource_label(resource)
    end
  end

  defp resource_row(_resources, _href_fun, _key, _label, nil), do: nil

  defp resource_row(resources, href_fun, key, label, value) do
    resolution = resource_resolution(resources, key)

    %{
      key: Atom.to_string(key),
      label: label,
      value: value,
      display_value: resource_display_value(key, value, resolution),
      status: resource_status(key, resolution),
      status_text: resource_status_text(key, resolution),
      href: href_fun.(key, value)
    }
  end

  defp resource_resolution(resources, :transport_id), do: resources.transport
  defp resource_resolution(resources, :source_endpoint_id), do: resources.source_endpoint
  defp resource_resolution(resources, :ground_station_id), do: resources.ground_station
  defp resource_resolution(resources, :link_id), do: resources.link_assignment
  defp resource_resolution(_resources, _key), do: nil

  defp resource_display_value(:selected_target, value, _resolution), do: value
  defp resource_display_value(:selected_id, value, _resolution), do: value

  defp resource_display_value(:ground_station_id, _value, %{label: label})
       when is_binary(label) and label != "",
       do: label

  defp resource_display_value(_key, value, resolution) do
    case resource_label(resolution) do
      nil -> value
      label -> label
    end
  end

  defp resource_status(key, _resolution) when key in [:selected_target, :selected_id],
    do: "context"

  defp resource_status(:ground_station_id, %{status: status}), do: Atom.to_string(status)
  defp resource_status(_key, nil), do: "missing"
  defp resource_status(_key, _resolution), do: "resolved"

  defp resource_status_text(key, _resolution) when key in [:selected_target, :selected_id],
    do: "context"

  defp resource_status_text(:ground_station_id, %{status: :inferred}), do: "inferred"
  defp resource_status_text(:ground_station_id, %{status: :unverified}), do: "unverified"
  defp resource_status_text(_key, nil), do: "missing"
  defp resource_status_text(_key, _resolution), do: "resolved"

  defp present_text?(value) do
    case resource_text(value) do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end

  defp resource_label(nil), do: nil

  defp resource_label(%{ground_station_id: ground_station_id} = ground_station)
       when is_binary(ground_station_id) do
    display_name = resource_value(ground_station, :display_name)

    if present_text?(display_name), do: display_name, else: ground_station_id
  end

  defp resource_label(%{transport_id: transport_id} = transport) when is_binary(transport_id) do
    display_name = resource_value(transport, :display_name)
    kind = resource_value(transport, :transport_kind)

    cond do
      present_text?(display_name) and not is_nil(kind) -> "#{display_name} / #{kind}"
      present_text?(display_name) -> display_name
      not is_nil(kind) -> "#{transport_id} / #{kind}"
      true -> transport_id
    end
  end

  defp resource_label(%{source_endpoint_id: source_endpoint_id} = source_endpoint)
       when is_binary(source_endpoint_id) do
    display_name = resource_value(source_endpoint, :display_name)
    source_ref = resource_value(source_endpoint, :source_ref)

    cond do
      present_text?(display_name) and present_text?(source_ref) ->
        "#{display_name} / #{source_ref}"

      present_text?(display_name) ->
        display_name

      present_text?(source_ref) ->
        "#{source_ref} / #{source_endpoint_id}"

      true ->
        source_endpoint_id
    end
  end

  defp resource_label(%{link_assignment_id: link_assignment_id} = link_assignment)
       when is_binary(link_assignment_id) do
    [
      resource_value(link_assignment, :spacecraft_id),
      resource_value(link_assignment, :source_endpoint_ref),
      resource_value(link_assignment, :direction)
    ]
    |> Enum.map(&resource_text/1)
    |> Enum.filter(&present_text?/1)
    |> case do
      [] -> link_assignment_id
      parts -> Enum.join(parts, " / ")
    end
  end

  defp resource_label(%{label: label}) when is_binary(label), do: label
  defp resource_label(_resource), do: nil

  defp ground_station_label(ground_station_id, nil), do: ground_station_id

  defp ground_station_label(ground_station_id, source_label),
    do: "#{ground_station_id} / #{source_label}"

  defp resource_value(resource, key) when is_map(resource),
    do: Map.get(resource, key, Map.get(resource, to_string(key)))

  defp resource_value(_resource, _key), do: nil

  defp resource_text(value) when is_atom(value), do: Atom.to_string(value)
  defp resource_text(value), do: value

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, metadata_atom_key(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp metadata_atom_key("antenna_id"), do: :antenna_id
  defp metadata_atom_key("ground_station_id"), do: :ground_station_id
  defp metadata_atom_key(_key), do: nil
end
