defmodule CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation do
  @moduledoc false

  @metadata_fields [
    :decision,
    :decision_reason,
    :execution_mode,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode,
    :stage,
    :request_group_id,
    :source_request_event_id,
    :workflow_id,
    :requested,
    :applied,
    :failed,
    :scope_kind,
    :scope_ids,
    :contact_ids,
    :resource_ids,
    :transport_ids,
    :source_endpoint_ids,
    :ground_station_ids,
    :scope_link_ids,
    :job_id,
    :count,
    :retried,
    :retry_nonretryable,
    :retry_skipped,
    :retry_errors,
    :retry_scope,
    :retry_run_ids,
    :retry_nonretryable_run_ids,
    :retry_nonretryable_event_ids,
    :retry_nonretryable_items,
    :retry_skipped_run_ids,
    :retry_skipped_event_ids,
    :retry_skipped_items,
    :retry_error_run_ids,
    :retry_error_event_ids,
    :retry_error_items,
    :queued_jobs,
    :failed_jobs,
    :result_event_id,
    :result_event_ids,
    :target_event_id,
    :target_run_id,
    :target_observation_identity_id
  ]

  @stable_attr_fields [
    {"decision", "decision"},
    {"decision_reason", "decision-reason"},
    {"execution_mode", "execution-mode"},
    {"dashboard_time_mode", "dashboard-time-mode"},
    {"dashboard_replay_run_id", "dashboard-replay-run-id"},
    {"dashboard_data_view", "dashboard-data-view"},
    {"dashboard_limit_mode", "dashboard-limit-mode"},
    {"request_group_id", "request-group-id"},
    {"source_request_event_id", "source-request-event-id"},
    {"workflow_id", "workflow-id"},
    {"requested", "requested"},
    {"applied", "applied"},
    {"failed", "failed"},
    {"scope_kind", "scope-kind"},
    {"scope_ids", "scope-ids"},
    {"contact_ids", "contact-ids"},
    {"resource_ids", "resource-ids"},
    {"transport_ids", "transport-ids"},
    {"source_endpoint_ids", "source-endpoint-ids"},
    {"ground_station_ids", "ground-station-ids"},
    {"scope_link_ids", "scope-link-ids"},
    {"result_event_id", "result-event-id"},
    {"result_event_ids", "result-event-ids"},
    {"target_event_id", "target-event-id"},
    {"target_run_id", "target-run-id"},
    {"target_observation_identity_id", "target-observation-identity-id"}
  ]

  @type t :: %__MODULE__{
          action: String.t(),
          status: String.t(),
          kind: String.t() | nil,
          reason: String.t() | nil,
          message: String.t() | nil,
          metadata: map(),
          metadata_json: String.t()
        }

  defstruct [
    :action,
    :kind,
    :reason,
    :message,
    status: "unknown",
    metadata: %{},
    metadata_json: "{}"
  ]

  @spec build(map() | term()) :: t() | nil
  def build(nil), do: nil

  def build(outcome) when is_map(outcome) do
    action = text_value(value(outcome, :action))

    if action do
      metadata = metadata(outcome)

      %__MODULE__{
        action: action,
        status: text_value(value(outcome, :status)) || "unknown",
        kind: text_value(value(outcome, :kind)),
        reason: text_value(value(outcome, :reason)),
        message: text_value(value(outcome, :message)),
        metadata: metadata,
        metadata_json: Jason.encode!(metadata)
      }
    end
  end

  def build(_outcome), do: nil

  @spec for_action(map() | term(), atom() | String.t()) :: t() | nil
  def for_action(outcome, action) do
    presentation = build(outcome)
    expected_action = text_value(action)

    case presentation do
      %{action: ^expected_action} -> presentation
      _other -> nil
    end
  end

  @spec stable_attrs(t() | nil, String.t(), keyword()) :: map()
  def stable_attrs(presentation, prefix, opts \\ [])

  def stable_attrs(nil, _prefix, _opts), do: %{}

  def stable_attrs(%__MODULE__{} = presentation, prefix, opts) when is_binary(prefix) do
    aliases = Keyword.get(opts, :aliases, %{})
    action_suffix = Keyword.get(opts, :action_suffix)

    presentation
    |> base_attrs(prefix, action_suffix)
    |> add_metadata_attrs(presentation.metadata, prefix, aliases)
  end

  defp metadata(outcome) do
    @metadata_fields
    |> Enum.reduce(%{}, fn field, acc ->
      case text_value(value(outcome, field)) do
        nil -> acc
        "" -> acc
        text -> Map.put(acc, Atom.to_string(field), text)
      end
    end)
  end

  defp value(outcome, key) when is_map(outcome) do
    Map.get(outcome, key, Map.get(outcome, Atom.to_string(key)))
  end

  defp base_attrs(%__MODULE__{} = presentation, prefix, action_suffix) do
    %{}
    |> put_attr(base_action_attr_name(prefix, action_suffix), presentation.action)
    |> put_attr("#{prefix}-status", presentation.status)
    |> put_attr("#{prefix}-kind", presentation.kind)
    |> put_attr("#{prefix}-reason", presentation.reason)
    |> put_attr("#{prefix}-metadata", presentation.metadata_json)
  end

  defp base_action_attr_name(prefix, nil), do: prefix
  defp base_action_attr_name(prefix, suffix) when is_binary(suffix), do: "#{prefix}-#{suffix}"

  defp add_metadata_attrs(attrs, metadata, prefix, aliases) do
    Enum.reduce(@stable_attr_fields, attrs, fn {field, default_suffix}, acc ->
      suffix = Map.get(aliases, field, default_suffix)
      put_attr(acc, "#{prefix}-#{suffix}", Map.get(metadata, field))
    end)
  end

  defp put_attr(attrs, _name, nil), do: attrs
  defp put_attr(attrs, _name, ""), do: attrs
  defp put_attr(attrs, name, value), do: Map.put(attrs, name, value)

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil
end
