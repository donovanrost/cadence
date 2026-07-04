defmodule Cadence.Dashboards.PublishReadinessPresentation do
  @moduledoc false

  alias Cadence.Dashboards.{DashboardAction, SourceActions, ValidationResult}

  def build(validation, freshness \\ nil)

  def build(nil, _freshness), do: nil

  def build(%ValidationResult{} = validation, %{state: "stale"} = freshness) do
    %{
      status: "stale",
      label: "needs re-check",
      message: stale_message(freshness),
      badge_class: "badge-warning",
      result: validation_result(:stale, freshness),
      issues: issues(validation)
    }
  end

  def build(%ValidationResult{} = validation, _freshness) do
    %{
      status: status(validation),
      label: label(validation),
      message: message(validation),
      badge_class: badge_class(validation),
      result: validation_result(validation),
      issues: issues(validation)
    }
  end

  def issue_message(%{code: :unsupported_widget_frame_contract, details: details})
      when is_map(details) do
    cond do
      observables = Map.get(details, :unsupported_observables) ->
        "Widget cannot use selected operational observables: #{detail_value(observables)}."

      source = Map.get(details, :requested_source) ->
        "Widget cannot use selected binding source: #{detail_value(source)}."

      true ->
        "Widget binding is not supported by the widget frame contract."
    end
  end

  def issue_message(%{code: :unsupported_widget_frame_contract}) do
    "Widget binding is not supported by the widget frame contract."
  end

  def issue_message(%{code: :invalid_runtime_default_context, details: details})
      when is_map(details) do
    "Dashboard runtime defaults include unsupported #{detail_value(Map.get(details, :context))} context."
  end

  def issue_message(%{code: :invalid_runtime_defaults}) do
    "Dashboard runtime defaults are not a valid context map."
  end

  def issue_message(%{code: :unready_publish_source_request, details: details})
      when is_map(details) do
    details
    |> Map.get(:source_warning_code)
    |> source_warning_message(details)
  end

  def issue_message(_issue), do: "Review the validation details below."

  def issue_detail_rows(%{
        code: :unready_publish_source_request,
        details: %{details: nested_details} = details
      })
      when is_map(nested_details) do
    details
    |> Map.drop([:details])
    |> detail_rows()
    |> Kernel.++(detail_rows(nested_details))
  end

  def issue_detail_rows(%{details: details}) when is_map(details) do
    detail_rows(details)
  end

  def issue_detail_rows(_issue), do: []

  defp detail_rows(details) when is_map(details) do
    details
    |> Enum.map(fn {key, value} ->
      %{label: detail_label(key), value: detail_value(value)}
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp status(%ValidationResult{valid?: false}), do: "blocked"
  defp status(%ValidationResult{warnings: []}), do: "clean"
  defp status(%ValidationResult{}), do: "warnings"

  defp label(%ValidationResult{valid?: false}), do: "blocked"
  defp label(%ValidationResult{warnings: []}), do: "ready"
  defp label(%ValidationResult{}), do: "warnings"

  defp message(%ValidationResult{valid?: false}) do
    "Resolve validation errors before publishing this draft."
  end

  defp message(%ValidationResult{warnings: []}) do
    "This draft is ready to publish."
  end

  defp message(%ValidationResult{}) do
    "This draft can publish, but retained content has warnings."
  end

  defp badge_class(%ValidationResult{valid?: false}), do: "badge-error"
  defp badge_class(%ValidationResult{warnings: []}), do: "badge-success"
  defp badge_class(%ValidationResult{}), do: "badge-warning"

  defp validation_result(:stale, freshness) do
    %{
      state: "needs_recheck",
      label: "needs re-check",
      message: stale_result_message(freshness)
    }
  end

  defp validation_result(%ValidationResult{valid?: false}) do
    %{
      state: "still_blocked",
      label: "still blocked",
      message: "Latest check still has publish blockers."
    }
  end

  defp validation_result(%ValidationResult{warnings: []}) do
    %{
      state: "resolved",
      label: "resolved",
      message: "Latest check found no publish blockers."
    }
  end

  defp validation_result(%ValidationResult{}) do
    %{
      state: "resolved_with_warnings",
      label: "resolved with warnings",
      message: "Latest check found no publish blockers, but warnings remain."
    }
  end

  defp stale_message(%{message: message}) when is_binary(message) and message != "" do
    "#{message} Re-check readiness before publishing."
  end

  defp stale_message(_freshness) do
    "Draft changed after this publish check. Re-check readiness before publishing."
  end

  defp stale_result_message(%{message: message}) when is_binary(message) and message != "" do
    message
  end

  defp stale_result_message(_freshness) do
    "This publish check is stale. Re-check readiness against the current draft."
  end

  defp issues(%ValidationResult{} = validation) do
    Enum.map(validation.errors, &issue(:error, &1)) ++
      Enum.map(validation.warnings, &issue(:warning, &1))
  end

  defp issue(severity, issue) do
    summary_rows = issue_summary_rows(issue)

    %{
      id: issue_id(severity, issue),
      severity: severity,
      severity_text: Atom.to_string(severity),
      badge_class: issue_badge_class(severity),
      code: issue_code(issue),
      message: issue_message(issue),
      action: issue_action(issue),
      detail_rows: issue_detail_rows(issue)
    }
    |> maybe_put_summary_rows(summary_rows)
  end

  defp issue_action(%{code: :unready_publish_source_request, details: details})
       when is_map(details) do
    details
    |> SourceActions.publish_readiness_action()
    |> source_readiness_action()
  end

  defp issue_action(%{code: :invalid_runtime_default_context}) do
    action(
      "Update runtime defaults",
      "Open dashboard context controls and choose a supported mission, scope, data realm, and source binding before publishing.",
      "dashboard_context"
    )
  end

  defp issue_action(%{code: :invalid_runtime_defaults}) do
    action(
      "Reset runtime defaults",
      "Save the draft after replacing invalid runtime defaults with a valid dashboard context map.",
      "dashboard_context"
    )
  end

  defp issue_action(%{code: :unsupported_widget_frame_contract}) do
    action(
      "Change widget binding",
      "Edit the affected widget so its source, observable, sampling, and value kind match the supported frame contract.",
      "dashboard_editor"
    )
  end

  defp issue_action(%{code: code}) when code in [:invalid_grid, "invalid_grid"] do
    action(
      "Fix dashboard grid",
      "Edit the dashboard layout so grid columns, row height, and gap values satisfy the document schema.",
      "dashboard_editor"
    )
  end

  defp issue_action(_issue), do: nil

  defp source_readiness_action(%DashboardAction{} = dashboard_action) do
    action(
      dashboard_action.label,
      dashboard_action.message || "Review the source readiness issue for this publish context.",
      publish_readiness_action_target(dashboard_action),
      dashboard_action.query
    )
    |> Map.put(:typed_action, typed_dashboard_action(dashboard_action))
  end

  defp source_readiness_action(_action), do: nil

  defp publish_readiness_action_target(%DashboardAction{target: :dashboard_editor}),
    do: "dashboard_editor"

  defp publish_readiness_action_target(%DashboardAction{target: target})
       when target in [:source_health, :source_inventory],
       do: "data_sources"

  defp publish_readiness_action_target(%DashboardAction{target: target}) when is_atom(target),
    do: Atom.to_string(target)

  defp issue_id(severity, issue) do
    [
      severity,
      issue_code(issue),
      issue_detail(issue, :placement_id),
      issue_detail(issue, :field),
      issue_detail(issue, :context),
      issue_detail(issue, :errors),
      issue_detail(issue, :widget_type_id),
      issue_source_warning_code(issue),
      issue_nested_detail(issue, :unsupported_observables)
    ]
    |> Enum.flat_map(&issue_id_parts/1)
    |> Enum.join(":")
  end

  defp issue_source_warning_code(%{details: details}) when is_map(details) do
    Map.get(details, :source_warning_code)
  end

  defp issue_source_warning_code(_issue), do: nil

  defp issue_detail(%{details: details}, key) when is_map(details), do: Map.get(details, key)
  defp issue_detail(_issue, _key), do: nil

  defp issue_nested_detail(%{details: %{details: nested_details}}, key)
       when is_map(nested_details) do
    Map.get(nested_details, key)
  end

  defp issue_nested_detail(_issue, _key), do: nil

  defp issue_id_parts(value) when is_list(value), do: Enum.flat_map(value, &issue_id_parts/1)
  defp issue_id_parts(nil), do: []
  defp issue_id_parts(""), do: []

  defp issue_id_parts(value) do
    [value |> detail_value() |> issue_id_part()]
  end

  defp issue_id_part(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_.-]+/, "-")
    |> String.trim("-")
  end

  defp issue_summary_rows(%{
         code: :unready_publish_source_request,
         details:
           %{
             source_warning_code: :unsupported_observable_scope,
             details: nested_details
           } = details
       })
       when is_map(nested_details) do
    [
      summary_row(:placement_id, "Placement", Map.get(details, :placement_id)),
      summary_row(:requested_scope, "Context", Map.get(nested_details, :requested_scope_kind)),
      summary_row(
        :unsupported_observables,
        "Observables",
        Map.get(nested_details, :unsupported_observables)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp issue_summary_rows(%{
         code: :unready_publish_source_request,
         details: %{source_warning_code: :unsupported_observable_scope} = details
       }) do
    [
      summary_row(:placement_id, "Placement", Map.get(details, :placement_id))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp issue_summary_rows(_issue), do: []

  defp summary_row(_key, _label, value) when value in [nil, []], do: nil

  defp summary_row(key, label, value) do
    %{key: Atom.to_string(key), label: label, value: detail_value(value)}
  end

  defp maybe_put_summary_rows(issue, []), do: issue
  defp maybe_put_summary_rows(issue, rows), do: Map.put(issue, :summary_rows, rows)

  defp unsupported_observable_scope_message(%{details: nested_details})
       when is_map(nested_details) do
    case Map.get(nested_details, :unsupported_observables) do
      [_ | _] = observables ->
        "Dashboard context cannot support selected operational observables: #{detail_value(observables)}."

      _observables ->
        "Dashboard context cannot support selected operational observables."
    end
  end

  defp unsupported_observable_scope_message(_details) do
    "Dashboard context cannot support selected operational observables."
  end

  defp source_warning_message(:unsupported_observable_scope, details),
    do: unsupported_observable_scope_message(details)

  defp source_warning_message(:unsupported_source_capability, _details),
    do: "Dashboard source cannot satisfy a planned widget request."

  defp source_warning_message(:missing_source_binding, _details),
    do: "Dashboard source binding cannot be resolved for the publish context."

  defp source_warning_message(:missing_data_source, _details),
    do: "Dashboard source binding references a missing data source."

  defp source_warning_message(:disabled_data_source, _details),
    do: "Dashboard source binding resolves to a disabled data source."

  defp source_warning_message(:source_unavailable, _details),
    do: "Dashboard source is unavailable for the publish context."

  defp source_warning_message(:source_connection_failed, details),
    do: source_connection_failed_message(details)

  defp source_warning_message(:source_degraded, _details),
    do: "Dashboard source is degraded for the publish context."

  defp source_warning_message(_other, _details),
    do: "Dashboard source readiness failed for the publish context."

  defp source_connection_failed_message(%{details: nested_details})
       when is_map(nested_details) do
    case Map.get(nested_details, :connection_test_result) ||
           Map.get(nested_details, "connection_test_result") do
      result when result in [:failed, "failed"] ->
        "Dashboard source connection test failed for the publish context."

      result when result in [:blocked, "blocked"] ->
        "Dashboard source connection test was blocked before adapter IO."

      _result ->
        "Dashboard source connection is not ready for the publish context."
    end
  end

  defp source_connection_failed_message(_details) do
    "Dashboard source connection is not ready for the publish context."
  end

  defp action(label, message, target, params \\ %{}) do
    %{label: label, message: message, target: target, params: params}
  end

  defp typed_dashboard_action(%DashboardAction{} = action) do
    %{
      "action_id" => action.action_id,
      "label" => action.label,
      "message" => action.message,
      "target" => typed_action_value(action.target),
      "kind" => typed_action_value(action.kind),
      "route" => action.route,
      "query" => typed_action_value(action.query),
      "context" => typed_action_value(action.context),
      "presentation" => typed_action_value(action.presentation),
      "source" => typed_action_value(action.source)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new()
  end

  defp typed_action_value(value) when is_atom(value), do: Atom.to_string(value)

  defp typed_action_value(value) when is_map(value) do
    value
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {to_string(key), typed_action_value(value)} end)
  end

  defp typed_action_value(value) when is_list(value),
    do: Enum.map(value, &typed_action_value/1)

  defp typed_action_value(value), do: value

  defp issue_badge_class(:error), do: "badge-error"
  defp issue_badge_class(:warning), do: "badge-warning"

  defp issue_code(%{code: code}) when is_atom(code), do: Atom.to_string(code)
  defp issue_code(%{code: code}) when is_binary(code), do: code
  defp issue_code(_issue), do: "unknown"

  defp detail_label(:requested_source), do: "Requested source"
  defp detail_label(:supported_sources), do: "Supported sources"
  defp detail_label(:requested_observables), do: "Requested observables"
  defp detail_label(:unsupported_observables), do: "Unsupported observables"
  defp detail_label(:supported_products), do: "Supported products"
  defp detail_label(:requested_source_products), do: "Requested source products"
  defp detail_label(:requested_products), do: "Requested products"
  defp detail_label(:requested_product_families), do: "Requested product families"
  defp detail_label(:supported_product_families), do: "Supported product families"
  defp detail_label(:supported_value_kinds), do: "Supported value kinds"
  defp detail_label(:requested_value_kinds), do: "Requested value kinds"
  defp detail_label(:widget_type_id), do: "Widget type"
  defp detail_label(:placement_id), do: "Placement"
  defp detail_label(:context), do: "Context"
  defp detail_label(:errors), do: "Errors"
  defp detail_label(:reason), do: "Reason"
  defp detail_label(:source_warning_code), do: "Source warning"
  defp detail_label(:source_warning_message), do: "Source message"
  defp detail_label(:severity), do: "Severity"
  defp detail_label(:details), do: "Details"
  defp detail_label(:requested_scope_kind), do: "Requested scope"
  defp detail_label(:requested_scope_ids), do: "Requested scope ids"
  defp detail_label(:supported_scopes), do: "Supported scopes"
  defp detail_label(key), do: to_string(key)

  defp detail_value(nil), do: "none"

  defp detail_value(value) when is_list(value),
    do: Enum.map_join(value, ", ", &detail_value/1)

  defp detail_value(value) when is_boolean(value), do: to_string(value)
  defp detail_value(value) when is_atom(value), do: Atom.to_string(value)
  defp detail_value(value) when is_binary(value), do: value
  defp detail_value(value) when is_number(value), do: to_string(value)
  defp detail_value(value), do: inspect(value)
end
