defmodule Cadence.Dashboards.SourceActions do
  @moduledoc """
  Builds typed dashboard actions for source-related warnings and evidence.

  Core dashboard code owns the operator intent, while web callers hydrate these
  route-free actions into mission-specific navigation.
  """

  alias Cadence.Dashboards.{DashboardAction, DataContext, PlannedSourceRequest, ScopeContext}

  @source_query_keys [
    :placement_id,
    :data_source_id,
    :source_binding_id,
    :binding_id,
    :logical_source,
    :realm,
    :time_mode,
    :time_axis,
    :replay_run_id,
    :scope_kind,
    :scope_id,
    :requested_scope_kind,
    :requested_scope_ids,
    :contact_id,
    :source_endpoint_id,
    :source_empty_reason,
    :requested_observables,
    :requested_sampling,
    :supported_sampling,
    :requested_products,
    :requested_source_products,
    :supported_products,
    :requested_product_families,
    :supported_product_families,
    :requested_value_kinds,
    :supported_value_kinds,
    :requested_shapes,
    :supported_shapes,
    :requested_time_axes,
    :supported_time_axes,
    :unsupported_observables,
    :supported_scopes,
    :connection_test_result,
    :connection_test_kind,
    :connection_test_message,
    :selected_evidence_kind,
    :selected_source_evidence_mode,
    :selected_source_evidence_state
  ]

  @source_context_keys [
    :source_request_id,
    :logical_source,
    :realm,
    :data_source_id,
    :source_binding_id,
    :binding_id,
    :dataset,
    :time_mode,
    :time_axis,
    :replay_run_id,
    :scope_kind,
    :scope_id,
    :requested_scope_kind,
    :requested_scope_ids,
    :contact_id,
    :source_endpoint_id,
    :source_endpoint_ids,
    :source_empty_reason,
    :requested_observables,
    :requested_realm,
    :requested_data_source_id,
    :requested_source_binding_id,
    :requested_dataset,
    :requested_validity_state,
    :placement_id,
    :requested_sampling,
    :supported_sampling,
    :supported_modes,
    :requested_products,
    :requested_source_products,
    :supported_products,
    :requested_product_families,
    :supported_product_families,
    :requested_value_kinds,
    :supported_value_kinds,
    :requested_value_types,
    :supported_value_types,
    :requested_shapes,
    :supported_shapes,
    :requested_time_axes,
    :supported_time_axes,
    :unsupported_observables,
    :supported_scopes,
    :connection_test_result,
    :connection_test_kind,
    :connection_test_message,
    :selected_evidence_kind,
    :selected_source_evidence_mode,
    :selected_source_evidence_state
  ]

  @type source_warning_code ::
          :missing_source_binding
          | :missing_data_source
          | :disabled_data_source
          | :unsupported_source_capability
          | :source_unavailable
          | :source_connection_failed
          | :source_degraded
          | :missing_replay_run_id
          | :missing_replay_source_binding
          | :replay_source_required
          | :invalid_data_source_configuration
          | :source_binding_interval_ambiguous
          | :unsupported_observable_scope

  @source_readiness_action_messages %{
    missing_source_binding: {
      "Create or select a source binding",
      "Open Data Sources and bind this dashboard's logical source to an active data source for the publish context.",
      :source_inventory
    },
    missing_data_source: {
      "Reconnect the source binding",
      "Open Data Sources and point the binding at an existing active source, or register the missing source.",
      :source_inventory
    },
    disabled_data_source: {
      "Enable or replace the data source",
      "Open Data Sources and enable the selected source, or move the binding to another active source.",
      :source_inventory
    },
    unsupported_source_capability: {
      "Use a compatible source",
      "Open Data Sources and choose a source whose capabilities support the widget request, or change the widget sampling requirements.",
      :source_inventory
    },
    source_unavailable: {
      "Restore source availability",
      "Probe or repair the source in Data Sources, then refresh publish readiness before publishing.",
      :source_health
    },
    source_connection_failed: {
      "Fix source connection",
      "Open Data Sources, inspect the failed connection test, and repair the adapter, credentials, or endpoint before refreshing publish readiness.",
      :source_health
    },
    source_degraded: {
      "Review degraded source health",
      "Open Data Sources, review the health event, and either accept a healthier binding or restore the current source.",
      :source_health
    },
    missing_replay_run_id: {
      "Select a replay run",
      "Choose a replay run before evaluating this dashboard in replay mode.",
      :source_inventory
    },
    missing_replay_source_binding: {
      "Bind replay data",
      "Open Data Sources and bind this dashboard's logical source to an active replay data source for the selected run.",
      :source_inventory
    },
    replay_source_required: {
      "Use a replay source",
      "Open Data Sources or runtime controls and select a replay realm/source for this replay-mode dashboard request.",
      :source_inventory
    },
    invalid_data_source_configuration: {
      "Fix source configuration",
      "Open Data Sources and correct the adapter, credentials, dataset, or endpoint configuration for the selected source.",
      :source_inventory
    },
    source_binding_interval_ambiguous: {
      "Resolve binding interval",
      "Open Data Sources and adjust binding activation intervals so the publish context resolves to one active binding.",
      :source_inventory
    },
    unsupported_observable_scope: {
      "Change widget context",
      "Open the dashboard editor and choose observables that support this context, or change the dashboard runtime context before publishing.",
      :dashboard_editor
    }
  }
  @source_readiness_codes Map.keys(@source_readiness_action_messages)
  @source_readiness_code_strings Map.new(@source_readiness_codes, &{Atom.to_string(&1), &1})

  @spec put_source_request_context(
          map(),
          PlannedSourceRequest.t() | nil,
          atom() | binary() | nil
        ) :: map()
  def put_source_request_context(details, request, logical_source \\ nil)

  def put_source_request_context(
        details,
        %PlannedSourceRequest{} = request,
        logical_source
      )
      when is_map(details) do
    logical_source = logical_source || request.logical_source
    data_context = request.data_context

    request_details =
      request.scope_context
      |> source_request_scope_context()
      |> Map.merge(%{
        time_mode: source_detail(request.time_context, :mode),
        time_axis: source_detail(request.time_context, :axis),
        replay_run_id:
          source_detail(request.time_context, :replay_run_id) ||
            DataContext.source_value(data_context, logical_source, :replay_run_id),
        requested_realm: DataContext.source_value(data_context, logical_source, :realm),
        requested_data_source_id:
          DataContext.source_value(data_context, logical_source, :data_source_id),
        requested_source_binding_id:
          DataContext.source_value(data_context, logical_source, :source_binding_id),
        requested_dataset: DataContext.source_value(data_context, logical_source, :dataset),
        requested_validity_state:
          DataContext.source_value(data_context, logical_source, :validity_state)
      })
      |> drop_empty_values()

    Map.merge(details, request_details)
  end

  def put_source_request_context(details, _request, _logical_source) when is_map(details),
    do: details

  defp source_request_scope_context(scope_context) do
    scope_context = ScopeContext.from_map(scope_context)
    kind = ScopeContext.primary_kind(scope_context)
    ids = ScopeContext.primary_ids(scope_context)
    contact_ids = ScopeContext.scope_ids(scope_context, :contact)

    %{
      requested_scope_kind: kind,
      requested_scope_ids: ids,
      requested_contact_id: List.first(contact_ids),
      requested_contact_ids: contact_ids
    }
  end

  @spec source_warning_actions(map(), keyword()) :: [DashboardAction.t()]
  def source_warning_actions(details, opts \\ []) when is_map(details) do
    details
    |> source_action_context()
    |> then(fn context ->
      [
        source_health_action(context, opts),
        source_inventory_action(context, opts)
      ]
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec put_source_warning_actions(map(), keyword()) :: map()
  def put_source_warning_actions(details, opts \\ []) when is_map(details) do
    actions = source_warning_actions(details, opts)

    if actions == [] do
      details
    else
      Map.put(details, :actions, merge_actions(Map.get(details, :actions), actions))
    end
  end

  @spec publish_readiness_action(map(), keyword()) :: DashboardAction.t() | nil
  def publish_readiness_action(details, opts \\ []) when is_map(details) do
    details
    |> source_readiness_code()
    |> source_readiness_action(details, opts)
  end

  @spec source_health_action(map(), keyword()) :: DashboardAction.t() | nil
  def source_health_action(context, opts \\ []) when is_map(context) do
    if source_actionable?(context) do
      %DashboardAction{
        action_id: Keyword.get(opts, :health_action_id, "dashboard-source-health-action"),
        label: Keyword.get(opts, :health_label, "Inspect source health"),
        message: Keyword.get(opts, :health_message),
        target: :source_health,
        kind: :invoke,
        query: source_action_query(context),
        context: context,
        source: Keyword.get(opts, :source, :warning)
      }
    end
  end

  @spec source_inventory_action(map(), keyword()) :: DashboardAction.t() | nil
  def source_inventory_action(context, opts \\ []) when is_map(context) do
    query = source_action_query(context)

    if map_size(query) > 0 do
      %DashboardAction{
        action_id: Keyword.get(opts, :inventory_action_id, "dashboard-source-inventory-action"),
        label: Keyword.get(opts, :inventory_label, "Source inventory"),
        message: Keyword.get(opts, :inventory_message),
        target: :source_inventory,
        kind: :invoke,
        query: query,
        context: context,
        source: Keyword.get(opts, :source, :warning)
      }
    end
  end

  defp source_action_context(details) do
    @source_context_keys
    |> Enum.reduce(%{}, fn key, context ->
      case source_detail(details, key) do
        nil -> context
        "" -> context
        value -> Map.put(context, normalize_context_key(key), value)
      end
    end)
  end

  defp source_action_query(context) do
    @source_query_keys
    |> Enum.reduce(%{}, fn key, query ->
      case source_detail(context, key) do
        nil -> query
        "" -> query
        value -> Map.put(query, Atom.to_string(normalize_context_key(key)), stringify(value))
      end
    end)
  end

  defp source_actionable?(context) do
    context
    |> source_action_query()
    |> map_size()
    |> Kernel.>(0)
  end

  defp source_readiness_action(code, details, opts) do
    case Map.get(@source_readiness_action_messages, code) do
      {label, message, target} ->
        context = source_readiness_context(details, code)
        target = source_readiness_action_target(code, context, target)
        label = source_readiness_action_label(code, context, label)
        message = source_readiness_action_message(code, context, message)
        query = source_action_query(context)

        %DashboardAction{
          action_id: Keyword.get(opts, :action_id, "dashboard-publish-source-readiness-action"),
          label: Keyword.get(opts, :label, label),
          message: Keyword.get(opts, :message, message),
          target: target,
          kind: :invoke,
          query: query,
          context: context,
          source: Keyword.get(opts, :source, :warning)
        }

      nil ->
        nil
    end
  end

  defp source_readiness_action_target(
         :unsupported_source_capability,
         %{logical_source: :operational_observables},
         _target
       ),
       do: :dashboard_editor

  defp source_readiness_action_target(_code, _context, target), do: target

  defp source_readiness_action_label(
         :unsupported_source_capability,
         %{logical_source: :operational_observables},
         _label
       ),
       do: "Review operational history binding"

  defp source_readiness_action_label(_code, _context, label), do: label

  defp source_readiness_action_message(
         :unsupported_source_capability,
         %{logical_source: :operational_observables},
         _message
       ) do
    "Open the widget editor and review the selected operational metric-history group, or choose a data source that supports the requested history capability."
  end

  defp source_readiness_action_message(_code, _context, message), do: message

  defp source_readiness_code(details) do
    details
    |> source_detail(:source_warning_code)
    |> case do
      code when code in @source_readiness_codes -> code
      code when is_binary(code) -> Map.get(@source_readiness_code_strings, code)
      _code -> nil
    end
  end

  defp source_readiness_context(details, code) do
    source_details =
      case source_detail(details, :details) do
        nested_details when is_map(nested_details) -> nested_details
        _nested_details -> %{}
      end

    merged_details =
      source_details
      |> Map.merge(Map.drop(details, [:details, "details"]))
      |> Map.put(:source_empty_reason, source_empty_reason(code, source_details))
      |> maybe_put_connection_test_selection(code, source_details)

    merged_details
    |> source_action_context()
    |> normalize_readiness_context_keys()
  end

  defp normalize_readiness_context_keys(context) do
    context
    |> maybe_copy(:supported_modes, :supported_sampling)
    |> maybe_copy(:requested_value_types, :requested_value_kinds)
    |> maybe_copy(:supported_value_types, :supported_value_kinds)
    |> maybe_copy(:requested_scope_kind, :scope_kind)
    |> maybe_copy(:requested_scope_ids, :scope_id)
  end

  defp maybe_copy(context, from_key, to_key) do
    case {Map.get(context, to_key), Map.get(context, from_key)} do
      {nil, value} when value not in [nil, ""] -> Map.put(context, to_key, value)
      _values -> context
    end
  end

  defp source_empty_reason(:source_connection_failed, source_details) do
    source_details
    |> source_detail(:connection_test_result)
    |> connection_test_empty_reason()
  end

  defp source_empty_reason(code, _source_details), do: code

  defp maybe_put_connection_test_selection(details, :source_connection_failed, source_details) do
    Map.merge(details, %{
      selected_evidence_kind: "source",
      selected_source_evidence_mode: "health",
      selected_source_evidence_state:
        source_details
        |> source_detail(:connection_test_result)
        |> connection_test_empty_reason()
    })
  end

  defp maybe_put_connection_test_selection(details, _code, _source_details), do: details

  defp connection_test_empty_reason(result) when result in [:blocked, "blocked"],
    do: "connection_test_blocked"

  defp connection_test_empty_reason(_result), do: "connection_test_failed"

  defp merge_actions(existing_actions, new_actions) do
    existing_actions
    |> List.wrap()
    |> Kernel.++(new_actions)
    |> Enum.uniq_by(&action_identity/1)
  end

  defp action_identity(%DashboardAction{action_id: action_id}) when is_binary(action_id),
    do: action_id

  defp action_identity(%DashboardAction{} = action), do: {action.target, action.query}
  defp action_identity(action), do: action

  defp normalize_context_key(:binding_id), do: :source_binding_id
  defp normalize_context_key(:source_endpoint_ids), do: :source_endpoint_id
  defp normalize_context_key(:requested_scope_kind), do: :scope_kind
  defp normalize_context_key(:requested_scope_ids), do: :scope_id
  defp normalize_context_key(key), do: key

  defp source_detail(map, :source_endpoint_id) when is_map(map) do
    direct_value =
      map
      |> Map.get(:source_endpoint_id, Map.get(map, "source_endpoint_id"))
      |> normalize_detail()

    direct_value || source_detail(map, :source_endpoint_ids)
  end

  defp source_detail(map, key) when is_atom(key) do
    map
    |> Map.get(key, Map.get(map, Atom.to_string(key)))
    |> normalize_detail()
  end

  defp source_detail(_map, _key), do: nil

  defp normalize_detail([value]), do: normalize_detail(value)

  defp normalize_detail([_value | _rest] = values) do
    values
    |> Enum.map(&normalize_detail/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(", ", &stringify/1)
  end

  defp normalize_detail([]), do: nil
  defp normalize_detail(value), do: value

  defp drop_empty_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> value in [nil, ""] end)
  end

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_map(value), do: inspect(value)
  defp stringify(value), do: to_string(value)
end
