defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContext do
  @moduledoc false

  @fields [
    :scope_kind,
    :scope_id,
    :scope_ids,
    :scope_context,
    :spacecraft_id,
    :time_mode,
    :time_from,
    :time_to,
    :time_axis,
    :replay_run_id,
    :time_validation,
    :realm,
    :data_view,
    :compare_data_view,
    :data_source_id,
    :source_binding_id,
    :limit_mode,
    :limit_mode_fallback,
    :hidden_marker_categories,
    :time_context,
    :data_context,
    :limit_context
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          scope_kind: binary() | nil,
          scope_id: binary() | nil,
          scope_ids: [binary()],
          scope_context: term(),
          spacecraft_id: binary() | nil,
          time_mode: binary(),
          time_from: binary() | nil,
          time_to: binary() | nil,
          time_axis: binary(),
          replay_run_id: binary() | nil,
          time_validation: binary(),
          realm: binary(),
          data_view: binary(),
          compare_data_view: binary() | nil,
          data_source_id: binary() | nil,
          source_binding_id: binary() | nil,
          limit_mode: binary(),
          limit_mode_fallback: map() | nil,
          hidden_marker_categories: [binary()] | nil,
          time_context: map(),
          data_context: map(),
          limit_context: map()
        }

  @field_set MapSet.new(@fields)

  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = context), do: context

  def new(context) when is_map(context) do
    context
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case context_field(key) do
        nil -> acc
        field -> Map.put(acc, field, value)
      end
    end)
    |> then(&struct!(__MODULE__, &1))
  end

  @spec changed?(map(), t() | map()) :: boolean()
  def changed?(assigns, context) when is_map(assigns) do
    context = new(context)

    assigns[:dashboard_scope_context] != context.scope_context or
      assigns[:dashboard_time_context] != context.time_context or
      assigns[:dashboard_data_context] != context.data_context or
      assigns[:dashboard_limit_context] != context.limit_context
  end

  @spec field_assigns(t() | map()) :: map()
  def field_assigns(context) do
    context = new(context)

    %{
      context_spacecraft_id: context.spacecraft_id,
      context_scope_kind: context.scope_kind,
      context_scope_id: context.scope_id,
      context_scope_ids: context.scope_ids || [],
      dashboard_scope_context: context.scope_context,
      dashboard_time_mode: context.time_mode,
      dashboard_time_from: context.time_from,
      dashboard_time_to: context.time_to,
      dashboard_time_axis: context.time_axis,
      dashboard_replay_run_id: context.replay_run_id,
      dashboard_time_validation: context.time_validation,
      dashboard_data_realm: context.realm,
      dashboard_data_view: context.data_view,
      dashboard_compare_data_view: context.compare_data_view,
      dashboard_data_source_id: context.data_source_id,
      dashboard_source_binding_id: context.source_binding_id,
      dashboard_limit_mode: context.limit_mode,
      dashboard_limit_mode_fallback: context.limit_mode_fallback,
      dashboard_hidden_marker_categories: context.hidden_marker_categories || [],
      dashboard_time_context: context.time_context,
      dashboard_data_context: context.data_context,
      dashboard_limit_context: context.limit_context
    }
  end

  defp context_field(key) when is_atom(key) do
    if MapSet.member?(@field_set, key), do: key
  end

  defp context_field(key) when is_binary(key) do
    key
    |> String.to_existing_atom()
    |> context_field()
  rescue
    ArgumentError -> nil
  end

  defp context_field(_key), do: nil
end
