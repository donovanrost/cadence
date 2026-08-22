defmodule Cadence.Dashboards.PublishReadinessPayload do
  @moduledoc """
  Builds auditable publish-readiness lifecycle payloads.

  LiveView decides when to record a readiness check; this module owns what the
  persisted event payload means.
  """

  alias Cadence.Dashboards.{Document, PublishReadinessPresentation, ValidationResult}

  @source_evidence_warning_reasons %{
    :stale_data => "source_watermark_stale",
    "stale_data" => "source_watermark_stale",
    :watermark_unknown => "source_watermark_unknown",
    "watermark_unknown" => "source_watermark_unknown",
    :unknown_watermark => "source_watermark_unknown",
    "unknown_watermark" => "source_watermark_unknown",
    :retention_gap => "source_retention_gap",
    "retention_gap" => "source_retention_gap"
  }

  @source_evidence_context_fields [
    {"source_request_id", [:source_request_id]},
    {"logical_source", [:logical_source]},
    {"placement_id", [:placement_id]},
    {"source_binding_id", [:source_binding_id, :binding_id]},
    {"data_source_id", [:data_source_id]},
    {"realm", [:realm]},
    {"dataset", [:dataset]},
    {"time_mode", [:time_mode]},
    {"time_axis", [:time_axis]},
    {"replay_run_id", [:replay_run_id]},
    {"requested_source_binding_id", [:requested_source_binding_id]},
    {"requested_data_source_id", [:requested_data_source_id]},
    {"connection_test_result", [:connection_test_result]},
    {"connection_test_kind", [:connection_test_kind]},
    {"connection_test_message", [:connection_test_message]}
  ]

  def publish_validation_freshness_for(document, summary, validation \\ nil)

  def publish_validation_freshness_for(%Document{} = document, summary, validation) do
    draft_version = Document.version(document)
    summary_draft_version = summary_version(summary, :draft_version)

    reason =
      draft_version
      |> publish_validation_freshness_reason(summary_draft_version)
      |> apply_source_evidence_reason(validation)

    %{
      evaluated_at: evaluated_at_text(),
      draft_version: version_text(draft_version),
      summary_draft_version: version_text(summary_draft_version),
      latest_version: version_text(summary_version(summary, :latest_version)),
      published_version: version_text(summary_version(summary, :published_version)),
      state: publish_validation_freshness_state(reason),
      state_label: publish_validation_freshness_label(reason),
      reason: reason,
      reason_label: publish_validation_freshness_reason_label(reason),
      message: publish_validation_freshness_message(reason)
    }
  end

  def publish_validation_freshness_for(_document, _summary, _validation), do: nil

  def publish_readiness_payload_for(document, validation, summary \\ nil)

  def publish_readiness_payload_for(
        %Document{} = document,
        %ValidationResult{} = validation,
        summary
      ) do
    issues = validation.errors ++ validation.warnings
    issue_summaries = publish_readiness_issue_summaries(validation)
    remediation_targets = publish_readiness_remediation_targets(issue_summaries)
    typed_remediation_actions = publish_readiness_typed_remediation_actions(issue_summaries)
    source_warning_codes = source_warning_codes(issues)
    source_evidence_contexts = source_evidence_contexts(issues)
    freshness = publish_validation_freshness_for(document, summary, validation)

    %{
      "draft_version" => Document.version(document),
      "result" => publish_readiness_result(validation),
      "valid" => validation.valid?,
      "error_count" => length(validation.errors),
      "warning_count" => length(validation.warnings),
      "issue_count" => length(issues),
      "issue_codes" => Enum.map(issues, &issue_code/1),
      "freshness_state" => freshness.state,
      "freshness_reason" => freshness.reason,
      "freshness_reason_label" => freshness.reason_label,
      "freshness_message" => freshness.message,
      "issue_summaries" => issue_summaries,
      "source_evidence_contexts" => source_evidence_contexts,
      "remediation_targets" => remediation_targets,
      "typed_remediation_actions" => typed_remediation_actions
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
    |> Map.put("source_warning_codes", source_warning_codes)
  end

  def publish_readiness_payload_for(_document, _validation, _summary), do: %{}

  defp evaluated_at_text do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp summary_version(summary, key) when is_map(summary), do: Map.get(summary, key)
  defp summary_version(_summary, _key), do: nil

  defp version_text(version) when is_integer(version), do: Integer.to_string(version)
  defp version_text(_version), do: "-"

  defp publish_validation_freshness_state("draft_current"), do: "current"
  defp publish_validation_freshness_state("draft_version_unknown"), do: "unknown"
  defp publish_validation_freshness_state(_reason), do: "stale"

  defp publish_validation_freshness_label("draft_current"), do: "current draft"
  defp publish_validation_freshness_label("draft_version_unknown"), do: "draft state unknown"
  defp publish_validation_freshness_label("draft_version_changed"), do: "stale draft"
  defp publish_validation_freshness_label("source_watermark_stale"), do: "source evidence stale"

  defp publish_validation_freshness_label("source_watermark_unknown"),
    do: "source evidence unknown"

  defp publish_validation_freshness_label("source_retention_gap"), do: "source retention gap"
  defp publish_validation_freshness_label(_reason), do: "stale evidence"

  defp publish_validation_freshness_reason(version, version), do: "draft_current"
  defp publish_validation_freshness_reason(_version, nil), do: "draft_version_unknown"

  defp publish_validation_freshness_reason(_version, _summary_version),
    do: "draft_version_changed"

  defp publish_validation_freshness_reason_label("draft_current"), do: "draft current"
  defp publish_validation_freshness_reason_label("draft_version_unknown"), do: "draft unknown"
  defp publish_validation_freshness_reason_label("draft_version_changed"), do: "draft changed"
  defp publish_validation_freshness_reason_label("source_watermark_stale"), do: "source stale"
  defp publish_validation_freshness_reason_label("source_watermark_unknown"), do: "source unknown"
  defp publish_validation_freshness_reason_label("source_retention_gap"), do: "retention gap"
  defp publish_validation_freshness_reason_label(_reason), do: "freshness unknown"

  defp publish_validation_freshness_message("draft_current") do
    "Publish readiness was evaluated against the current draft version."
  end

  defp publish_validation_freshness_message("draft_version_unknown") do
    "The current draft version could not be compared to the dashboard summary."
  end

  defp publish_validation_freshness_message("draft_version_changed") do
    "The dashboard draft changed after this publish readiness check."
  end

  defp publish_validation_freshness_message("source_watermark_stale") do
    "Source watermark evidence is stale; re-check readiness after source data advances."
  end

  defp publish_validation_freshness_message("source_watermark_unknown") do
    "Source watermark evidence is unknown; re-check readiness after source freshness is proven."
  end

  defp publish_validation_freshness_message("source_retention_gap") do
    "Requested data crosses a source retention gap; re-check readiness after adjusting time range or source retention."
  end

  defp publish_validation_freshness_message(_reason),
    do: "Publish readiness freshness is unknown."

  defp apply_source_evidence_reason("draft_current", %ValidationResult{} = validation) do
    source_evidence_reason(validation) || "draft_current"
  end

  defp apply_source_evidence_reason(reason, _validation), do: reason

  defp source_evidence_reason(%ValidationResult{warnings: warnings}) when is_list(warnings) do
    warnings
    |> Enum.find_value(&source_evidence_issue_reason/1)
  end

  defp source_evidence_reason(_validation), do: nil

  defp source_evidence_issue_reason(%{code: code, details: details}) do
    Map.get(@source_evidence_warning_reasons, code) ||
      details
      |> source_evidence_warning_code()
      |> then(&Map.get(@source_evidence_warning_reasons, &1))
  end

  defp source_evidence_issue_reason(_issue), do: nil

  defp source_evidence_warning_code(details) when is_map(details) do
    Map.get(details, :source_warning_code) || Map.get(details, "source_warning_code")
  end

  defp source_evidence_warning_code(_details), do: nil

  defp publish_readiness_result(%ValidationResult{valid?: false}), do: "still_blocked"
  defp publish_readiness_result(%ValidationResult{warnings: []}), do: "resolved"
  defp publish_readiness_result(%ValidationResult{}), do: "resolved_with_warnings"

  defp issue_code(%{code: code}) when is_atom(code), do: Atom.to_string(code)
  defp issue_code(%{code: code}) when is_binary(code), do: code
  defp issue_code(_issue), do: "unknown"

  defp source_warning_codes(issues) do
    issues
    |> Enum.map(&source_warning_code/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp source_warning_code(%{details: %{source_warning_code: code}}) when is_atom(code),
    do: Atom.to_string(code)

  defp source_warning_code(%{details: %{source_warning_code: code}}) when is_binary(code),
    do: code

  defp source_warning_code(_issue), do: nil

  defp source_evidence_contexts(issues) do
    issues
    |> Enum.map(&source_evidence_context/1)
    |> Enum.reject(&(map_size(&1) == 0))
    |> Enum.uniq()
  end

  defp source_evidence_context(issue) when is_map(issue) do
    warning_code = source_warning_code(issue)

    if warning_code in [nil, ""] do
      %{}
    else
      source_evidence_context_for(issue, warning_code)
    end
  end

  defp source_evidence_context(_issue), do: %{}

  defp source_evidence_context_for(issue, warning_code) do
    details = issue_details(issue)
    scopes = [details, issue_details(details)]

    @source_evidence_context_fields
    |> Enum.reduce(%{}, &put_source_evidence_context_field(&1, &2, scopes))
    |> maybe_put_source_evidence_code(warning_code)
  end

  defp put_source_evidence_context_field({output_key, input_keys}, context, scopes) do
    case source_evidence_context_value(scopes, input_keys) do
      nil -> context
      value -> Map.put(context, output_key, source_evidence_context_text(value))
    end
  end

  defp maybe_put_source_evidence_code(context, code) when code in [nil, "", "unknown"],
    do: context

  defp maybe_put_source_evidence_code(context, code),
    do: Map.put(context, "warning_code", to_string(code))

  defp source_evidence_context_value(scopes, input_keys) do
    Enum.find_value(input_keys, fn key ->
      Enum.find_value(scopes, &source_evidence_detail_value(&1, key))
    end)
  end

  defp source_evidence_detail_value(details, key) when is_map(details) and is_atom(key) do
    Map.get(details, key) || Map.get(details, Atom.to_string(key))
  end

  defp source_evidence_detail_value(_details, _key), do: nil

  defp source_evidence_context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp source_evidence_context_text(value) when is_binary(value), do: value
  defp source_evidence_context_text(value), do: to_string(value)

  defp issue_details(%{details: details}) when is_map(details), do: details
  defp issue_details(%{"details" => details}) when is_map(details), do: details
  defp issue_details(details) when is_map(details), do: %{}

  defp publish_readiness_issue_summaries(%ValidationResult{} = validation) do
    validation
    |> PublishReadinessPresentation.build()
    |> Map.get(:issues, [])
    |> Enum.map(&publish_readiness_issue_summary/1)
  end

  defp publish_readiness_issue_summary(issue) when is_map(issue) do
    %{
      "id" => Map.get(issue, :id),
      "severity" => Map.get(issue, :severity_text),
      "code" => Map.get(issue, :code),
      "message" => Map.get(issue, :message),
      "action" => publish_readiness_action_summary(Map.get(issue, :action), Map.get(issue, :id))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new()
  end

  defp publish_readiness_action_summary(action, issue_id) when is_map(action) do
    %{
      "issue_id" => issue_id,
      "label" => Map.get(action, :label),
      "target" => Map.get(action, :target),
      "message" => Map.get(action, :message),
      "params" =>
        action
        |> Map.get(:params, %{})
        |> publish_readiness_action_params()
        |> maybe_put_selected_publish_issue(issue_id),
      "typed_action" => publish_readiness_typed_action(Map.get(action, :typed_action), issue_id)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new()
  end

  defp publish_readiness_action_summary(_action, _issue_id), do: nil

  defp publish_readiness_typed_action(typed_action, issue_id) when is_map(typed_action) do
    typed_action
    |> publish_readiness_typed_action_value()
    |> maybe_put_typed_action_issue_id(issue_id)
  end

  defp publish_readiness_typed_action(_typed_action, _issue_id), do: nil

  defp publish_readiness_typed_action_value(value) when is_map(value) do
    value
    |> Enum.reject(fn {_key, value} -> value in [nil, "", %{}] end)
    |> Map.new(fn {key, value} ->
      {to_string(key), publish_readiness_typed_action_value(value)}
    end)
  end

  defp publish_readiness_typed_action_value(value) when is_list(value) do
    Enum.map(value, &publish_readiness_typed_action_value/1)
  end

  defp publish_readiness_typed_action_value(value) when is_atom(value), do: Atom.to_string(value)
  defp publish_readiness_typed_action_value(value), do: value

  defp maybe_put_typed_action_issue_id(action, issue_id)
       when is_map(action) and is_binary(issue_id) and issue_id != "" do
    Map.put_new(action, "issue_id", issue_id)
  end

  defp maybe_put_typed_action_issue_id(action, _issue_id), do: action

  defp publish_readiness_action_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp publish_readiness_action_params(_params), do: %{}

  defp maybe_put_selected_publish_issue(params, issue_id)
       when is_binary(issue_id) and issue_id != "" do
    Map.put_new(params, "selected_publish_issue", issue_id)
  end

  defp maybe_put_selected_publish_issue(params, _issue_id), do: params

  defp publish_readiness_remediation_targets(issue_summaries) do
    issue_summaries
    |> Enum.map(&Map.get(&1, "action"))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn action ->
      {Map.get(action, "target"), Map.get(action, "label"), Map.get(action, "params", %{})}
    end)
  end

  defp publish_readiness_typed_remediation_actions(issue_summaries) do
    issue_summaries
    |> Enum.map(&Map.get(&1, "action"))
    |> Enum.map(&typed_remediation_action/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&typed_remediation_action_identity/1)
  end

  defp typed_remediation_action(%{"typed_action" => typed_action}) when is_map(typed_action),
    do: typed_action

  defp typed_remediation_action(_action), do: nil

  defp typed_remediation_action_identity(action) when is_map(action) do
    {
      Map.get(action, "action_id"),
      Map.get(action, "target"),
      Map.get(action, "query", %{}),
      Map.get(action, "issue_id")
    }
  end

  defp typed_remediation_action_identity(action), do: action
end
