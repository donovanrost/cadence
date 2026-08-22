defmodule Cadence.Dashboards.DataLinkResolver.Support do
  @moduledoc """
  Shared inspector construction and normalization for data-link target resolvers.

  Target modules supply persisted-record rows, related links, and actions. This
  module keeps the common inspector contract and dashboard context projection
  consistent across those modules.
  """

  alias Cadence.Dashboards.{DataLink, DataLinkInspector, TelemetryActions}

  @spec inspector(
          DataLink.t(),
          DataLinkInspector.status(),
          binary() | nil,
          [map() | nil],
          [DataLink.t() | nil],
          [struct()] | nil
        ) :: DataLinkInspector.t()
  def inspector(link, status, message, rows, related_links \\ [], actions \\ nil)

  def inspector(
        %DataLink{} = link,
        status,
        message,
        rows,
        related_links,
        actions
      ) do
    DataLinkInspector.new(%{
      status: status,
      status_text: Atom.to_string(status),
      title: title(link),
      message: message,
      target: link.target,
      target_text: target_text(link.target),
      target_id: link.target_id,
      link_id: link.link_id,
      link_label: link.label,
      source: link.source,
      source_text: target_text(link.source),
      source_context: source_context(link.context),
      rows: Enum.reject(rows, &is_nil/1),
      context_rows: context_rows(link.context),
      navigation: navigation_context(link.context),
      related_links: related_links |> Enum.reject(&is_nil/1) |> dedupe_related_links(),
      actions: actions || telemetry_actions(link, source: :data_link_panel)
    })
  end

  @spec telemetry_actions(DataLink.t(), keyword()) :: [struct()]
  def telemetry_actions(%DataLink{} = link, opts) do
    link
    |> TelemetryActions.explore_action_from_data_link(opts)
    |> List.wrap()
  end

  @spec related_link(DataLink.t(), atom(), term(), binary(), atom() | nil) ::
          DataLink.t() | nil
  def related_link(source_link, target, target_id, label, relationship_kind \\ nil)

  def related_link(
        %DataLink{} = source_link,
        target,
        target_id,
        label,
        relationship_kind
      ) do
    case string_id(target_id) do
      nil ->
        nil

      target_id ->
        %DataLink{
          link_id: related_link_id(target, target_id),
          label: label,
          target: target,
          target_id: target_id,
          relationship_kind: relationship_kind,
          context: source_link.context,
          presentation: :side_panel,
          source: :annotation
        }
    end
  end

  @spec row(binary(), term()) :: map() | nil
  def row(_label, nil), do: nil
  def row(_label, ""), do: nil
  def row(label, value), do: %{label: label, value: value_text(value)}

  @spec context_value(term(), atom()) :: term()
  def context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  def context_value(_context, _key), do: nil

  @spec context_map_or_empty(term()) :: map()
  def context_map_or_empty(context) when is_map(context), do: context
  def context_map_or_empty(_context), do: %{}

  @spec metadata_value(term(), atom() | [atom()]) :: term()
  def metadata_value(metadata, keys) when is_list(keys) do
    Enum.find_value(keys, &metadata_value(metadata, &1))
  end

  def metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  def metadata_value(_metadata, _key), do: nil

  @spec state_value(term(), atom()) :: term()
  def state_value(state, key), do: context_value(state, key)

  @spec string_id(term()) :: binary() | nil
  def string_id(value) when is_binary(value) and value != "", do: value
  def string_id(_value), do: nil

  @spec data_ref_text(term()) :: binary() | nil
  def data_ref_text(nil), do: nil
  def data_ref_text(value) when is_atom(value), do: Atom.to_string(value)
  def data_ref_text(value) when is_binary(value), do: value
  def data_ref_text(value), do: to_string(value)

  @spec value_text(term()) :: binary()
  def value_text(value) when is_boolean(value), do: to_string(value)
  def value_text(value) when is_atom(value), do: Atom.to_string(value)
  def value_text(value) when is_binary(value), do: value
  def value_text(value) when is_integer(value), do: Integer.to_string(value)
  def value_text(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  def value_text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def value_text(values) when is_list(values), do: Enum.map_join(values, ",", &value_text/1)
  def value_text(value), do: inspect(value)

  @spec target_text(atom() | binary() | nil) :: binary()
  def target_text(nil), do: "unknown"

  def target_text(target) when is_atom(target) do
    target
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  def target_text(target) when is_binary(target), do: String.replace(target, "_", " ")

  defp related_link_id(target, target_id), do: "inspector:#{target}:#{target_id}"

  defp dedupe_related_links(links) do
    Enum.uniq_by(links, &{&1.target, &1.target_id})
  end

  defp source_context(context) when is_map(context) do
    %{
      realm: nested_context_value(context, :data, :realm),
      data_view: nested_context_value(context, :data, :view),
      data_source_id: nested_context_value(context, :data, :data_source_id),
      source_binding_id: nested_context_value(context, :data, :source_binding_id),
      time_mode: nested_context_value(context, :time, :mode),
      time_axis: nested_context_value(context, :time, :axis),
      replay_run_id: replay_run_id(context),
      placement_id: nested_context_value(context, :selection, :placement_id),
      timestamp_ms: nested_context_value(context, :selection, :timestamp_ms)
    }
    |> Enum.flat_map(fn
      {_key, value} when value in [nil, ""] -> []
      {key, value} -> [{key, value_text(value)}]
    end)
    |> Map.new()
  end

  defp source_context(_context), do: %{}

  defp context_rows(context) when is_map(context) do
    [
      row("Organization", context_value(context, :organization_id)),
      row("Mission", context_value(context, :mission_id)),
      row("Source request", context_value(context, :source_request_id)),
      row("Logical source", context_value(context, :logical_source)),
      row("Observable", context_value(context, :observable_id)),
      row("Scope", context_value(context, :scope) |> primary_scope()),
      row("Time mode", nested_context_value(context, :time, :mode)),
      row("Time axis", nested_context_value(context, :time, :axis)),
      row("Replay run", replay_run_id(context)),
      row("From", nested_context_value(context, :time, :from)),
      row("To", nested_context_value(context, :time, :to)),
      row("Data realm", nested_context_value(context, :data, :realm)),
      row("Data view", nested_context_value(context, :data, :view)),
      row("Series role", nested_context_value(context, :selection, :series_role)),
      row("Compare of", nested_context_value(context, :selection, :compare_of)),
      row("Data source", nested_context_value(context, :data, :data_source_id)),
      row("Source binding", nested_context_value(context, :data, :source_binding_id)),
      row("Limit mode", nested_context_value(context, :limit, :semantics_mode)),
      row("Sampling", nested_context_value(context, :sampling, :mode))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp context_rows(_context), do: []

  defp navigation_context(context) when is_map(context) do
    from =
      context
      |> nested_context_value(:navigation, :from)
      |> navigation_from_context()

    trail =
      context
      |> nested_context_value(:navigation, :trail)
      |> navigation_trail_context()

    %{from: from, trail: trail}
    |> Enum.reject(fn
      {_key, value} when value in [nil, []] -> true
      {_key, value} when is_map(value) -> map_size(value) == 0
      _entry -> false
    end)
    |> Map.new()
    |> case do
      navigation when map_size(navigation) > 0 -> navigation
      _empty -> nil
    end
  end

  defp navigation_context(_context), do: nil

  defp navigation_from_context(from) when is_map(from) do
    %{
      link_id: context_value(from, :link_id),
      target: context_value(from, :target),
      target_id: context_value(from, :target_id),
      label: context_value(from, :label),
      relationship_kind: context_value(from, :relationship_kind),
      relationship_label: context_value(from, :relationship_label)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp navigation_from_context(_from), do: %{}

  defp navigation_trail_context(entries) when is_list(entries) do
    entries
    |> Enum.map(&navigation_from_context/1)
    |> Enum.reject(&(&1 == %{}))
    |> Enum.take(-3)
  end

  defp navigation_trail_context(_entries), do: []

  defp title(%DataLink{label: label}) when is_binary(label) and label != "", do: label
  defp title(%DataLink{target: target}), do: target_text(target)

  defp primary_scope(nil), do: nil
  defp primary_scope(%{primary: primary}), do: primary_scope(primary)
  defp primary_scope(%{"primary" => primary}), do: primary_scope(primary)

  defp primary_scope(%{} = primary) do
    kind = context_value(primary, :kind)
    mode = context_value(primary, :mode)
    ids = context_value(primary, :ids)

    [kind, mode, ids]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(":", &value_text/1)
  end

  defp primary_scope(other), do: other

  @spec nested_context_value(term(), atom(), atom()) :: term()
  def nested_context_value(context, section, key) do
    context
    |> context_value(section)
    |> context_value(key)
  end

  @spec replay_run_id(term()) :: term()
  def replay_run_id(context) do
    nested_context_value(context, :time, :replay_run_id) ||
      nested_context_value(context, :data, :replay_run_id) ||
      context_value(context, :replay_run_id)
  end
end
