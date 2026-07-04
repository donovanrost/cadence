defmodule CadenceWeb.OpsDashboardShowLive.RuntimeAssigns do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec runtime_query_attrs(Phoenix.LiveView.Socket.t() | map(), map()) :: map()
  def runtime_query_attrs(socket_or_assigns, defaults \\ %{}) when is_map(defaults) do
    assigns = normalize(socket_or_assigns)

    %{
      selected_ref: Map.get(assigns, :dashboard_selected_data_ref),
      selection_query: Map.get(assigns, :dashboard_selection_query),
      evidence_query: Map.get(assigns, :dashboard_evidence_query),
      scope_kind: Map.get(assigns, :context_scope_kind),
      scope_id: Map.get(assigns, :context_scope_id),
      scope_ids: Map.get(assigns, :context_scope_ids, []),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      time_from: Map.get(assigns, :dashboard_time_from),
      time_to: Map.get(assigns, :dashboard_time_to),
      time_axis: Map.get(assigns, :dashboard_time_axis),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      realm: Map.get(assigns, :dashboard_data_realm),
      data_view: Map.get(assigns, :dashboard_data_view),
      compare_data_view: Map.get(assigns, :dashboard_compare_data_view),
      data_source_id: Map.get(assigns, :dashboard_data_source_id),
      source_binding_id: Map.get(assigns, :dashboard_source_binding_id),
      limit_mode: Map.get(assigns, :dashboard_limit_mode)
    }
    |> Map.merge(defaults)
  end

  @spec runtime_context(Phoenix.LiveView.Socket.t() | map()) :: RuntimeContext.t()
  def runtime_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    RuntimeContext.new(%{
      scope_kind: Map.get(assigns, :context_scope_kind),
      scope_id: Map.get(assigns, :context_scope_id),
      scope_ids: Map.get(assigns, :context_scope_ids, []),
      scope_context: Map.get(assigns, :dashboard_scope_context),
      spacecraft_id: Map.get(assigns, :context_spacecraft_id),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      time_from: Map.get(assigns, :dashboard_time_from),
      time_to: Map.get(assigns, :dashboard_time_to),
      time_axis: Map.get(assigns, :dashboard_time_axis),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      time_validation: Map.get(assigns, :dashboard_time_validation),
      realm: Map.get(assigns, :dashboard_data_realm),
      data_view: Map.get(assigns, :dashboard_data_view),
      compare_data_view: Map.get(assigns, :dashboard_compare_data_view),
      data_source_id: Map.get(assigns, :dashboard_data_source_id),
      source_binding_id: Map.get(assigns, :dashboard_source_binding_id),
      limit_mode: Map.get(assigns, :dashboard_limit_mode),
      time_context: Map.get(assigns, :dashboard_time_context, %{}) || %{},
      data_context: Map.get(assigns, :dashboard_data_context, %{}) || %{},
      limit_context: Map.get(assigns, :dashboard_limit_context, %{}) || %{}
    })
  end

  @spec data_link_runtime_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def data_link_runtime_context(socket_or_assigns) do
    context = runtime_context(socket_or_assigns)

    %{
      time: context.time_context,
      data: context.data_context,
      limit: context.limit_context
    }
  end

  @spec runtime_invalidation_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def runtime_invalidation_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    %{
      data_realm: Map.get(assigns, :dashboard_data_realm),
      engine_result: Map.get(assigns, :dashboard_engine_result),
      time_context: Map.get(assigns, :dashboard_time_context),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      context_since: Map.get(assigns, :dashboard_runtime_context_since),
      edit_mode?: Map.get(assigns, :edit_mode?)
    }
  end

  @spec engine_request_attrs(Phoenix.LiveView.Socket.t() | map(), atom()) :: map()
  def engine_request_attrs(socket_or_assigns, resolve_mode) do
    assigns = normalize(socket_or_assigns)
    scope = Map.fetch!(assigns, :current_scope)
    mission = Map.fetch!(assigns, :current_mission)
    document = Map.fetch!(assigns, :dashboard_document)
    context = runtime_context(assigns)

    %{
      organization_id: value(scope, :organization_id),
      mission_id: value(mission, :mission_id),
      dashboard_id: value(document, :dashboard_id),
      document: document,
      document_mode: Map.get(assigns, :dashboard_document_mode),
      resolve_mode: resolve_mode,
      scope_context: context.scope_context,
      time_context: context.time_context,
      data_context: context.data_context,
      limit_context: context.limit_context
    }
  end

  defp value(container, key) when is_atom(key) and is_map(container) do
    Map.get(container, key, Map.get(container, Atom.to_string(key)))
  end
end
