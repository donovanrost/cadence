defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryParams do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{EvidenceQuery, SelectionQuery}

  @fields [
    :selected_ref,
    :selection_query,
    :evidence_query,
    :scope_kind,
    :scope_id,
    :scope_ids,
    :time_mode,
    :time_from,
    :time_to,
    :time_axis,
    :replay_run_id,
    :realm,
    :default_realm,
    :data_view,
    :default_data_view,
    :compare_data_view,
    :data_source_id,
    :source_binding_id,
    :default_source_binding_id,
    :limit_mode,
    :hidden_markers
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          selected_ref: map() | nil,
          selection_query: SelectionQuery.t() | map() | nil,
          evidence_query: EvidenceQuery.t() | map() | nil,
          scope_kind: binary() | nil,
          scope_id: binary() | nil,
          scope_ids: [binary()],
          time_mode: binary() | nil,
          time_from: binary() | nil,
          time_to: binary() | nil,
          time_axis: binary() | nil,
          replay_run_id: binary() | nil,
          realm: binary() | nil,
          default_realm: binary() | nil,
          data_view: binary() | nil,
          default_data_view: binary() | nil,
          compare_data_view: binary() | nil,
          data_source_id: binary() | nil,
          source_binding_id: binary() | nil,
          default_source_binding_id: binary() | nil,
          limit_mode: binary() | nil,
          hidden_markers: binary() | nil
        }

  @field_set MapSet.new(@fields)

  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = params), do: params

  def new(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case query_field(key) do
        nil -> acc
        field -> Map.put(acc, field, value)
      end
    end)
    |> then(&struct!(__MODULE__, &1))
  end

  @spec to_params(t() | map()) :: map()
  def to_params(attrs) when is_map(attrs) do
    params = new(attrs)
    scope_ids = scope_ids(params.scope_ids, params.scope_id)

    selection_query =
      SelectionQuery.to_params(
        SelectionQuery.from_ref(params.selected_ref) ||
          params.selection_query ||
          %{}
      )

    evidence_query = EvidenceQuery.to_params(params.evidence_query)

    %{
      "spacecraft_id" => spacecraft_scope_query(params.scope_kind, params.scope_id, scope_ids),
      "scope_kind" => generic_scope_kind_query(params.scope_kind, scope_ids),
      "scope_id" => generic_scope_id_query(params.scope_kind, params.scope_id, scope_ids),
      "scope_ids" => generic_scope_ids_query(scope_ids),
      "time_mode" => maybe_non_default(params.time_mode, "live"),
      "from" => params.time_from,
      "to" => params.time_to,
      "time_axis" => maybe_non_default(params.time_axis, default_time_axis(params.time_mode)),
      "replay_run_id" => params.replay_run_id,
      "realm" => maybe_non_default(params.realm, params.default_realm),
      "data_view" => maybe_non_default(params.data_view, params.default_data_view),
      "compare_data_view" => params.compare_data_view,
      "data_source_id" => params.data_source_id,
      "source_binding_id" =>
        current_source_binding_query(params.source_binding_id, params.default_source_binding_id),
      "limit_mode" => maybe_non_default(params.limit_mode, "observed"),
      "hidden_markers" => params.hidden_markers
    }
    |> Map.merge(selection_query)
    |> Map.merge(evidence_query)
    |> Map.merge(current_panel_query(selection_query, evidence_query))
  end

  def to_params(_attrs), do: %{}

  @spec compact(map()) :: map()
  def compact(query) when is_map(query) do
    query
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  def compact(_query), do: %{}

  @spec current_panel_query(SelectionQuery.t() | map() | nil, EvidenceQuery.t() | map() | nil) ::
          map()
  def current_panel_query(selection_query, evidence_query) do
    cond do
      EvidenceQuery.query?(evidence_query) ->
        %{"panel" => "evidence"}

      SelectionQuery.query?(selection_query) ->
        %{"panel" => "data_link"}

      true ->
        %{}
    end
  end

  defp query_field(key) when is_atom(key) do
    if MapSet.member?(@field_set, key), do: key
  end

  defp query_field(key) when is_binary(key) do
    key
    |> String.to_existing_atom()
    |> query_field()
  rescue
    ArgumentError -> nil
  end

  defp query_field(_key), do: nil

  defp scope_ids(ids, fallback_id) do
    ids =
      ids
      |> List.wrap()
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    if ids == [] and is_binary(fallback_id) and fallback_id != "" do
      [fallback_id]
    else
      ids
    end
  end

  defp spacecraft_scope_query("spacecraft", spacecraft_id, [single_id]),
    do: spacecraft_id || single_id

  defp spacecraft_scope_query(_scope_kind, _scope_id, _scope_ids), do: nil

  defp generic_scope_kind_query("spacecraft", []), do: nil
  defp generic_scope_kind_query("spacecraft", [_single_id]), do: nil
  defp generic_scope_kind_query(scope_kind, _scope_ids), do: scope_kind

  defp generic_scope_id_query("spacecraft", _scope_id, [_single_id]), do: nil
  defp generic_scope_id_query(_scope_kind, scope_id, [single_id]), do: scope_id || single_id
  defp generic_scope_id_query(_scope_kind, _scope_id, _scope_ids), do: nil

  defp generic_scope_ids_query([_single_id]), do: nil

  defp generic_scope_ids_query(scope_ids) when length(scope_ids) > 1,
    do: Enum.join(scope_ids, ",")

  defp generic_scope_ids_query(_scope_ids), do: nil

  defp current_source_binding_query(nil, default_source_binding_id)
       when is_binary(default_source_binding_id),
       do: "primary"

  defp current_source_binding_query(source_binding_id, _default_source_binding_id),
    do: source_binding_id

  defp maybe_non_default(value, value), do: nil
  defp maybe_non_default(value, _default), do: value

  defp default_time_axis(mode) when mode in ["archive", :archive], do: "receipt_time"
  defp default_time_axis(_mode), do: "generation_time"
end
