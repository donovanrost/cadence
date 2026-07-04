defmodule CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation do
  @moduledoc false

  @metadata_fields [
    :decision,
    :decision_reason,
    :execution_mode,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_limit_mode,
    :stage,
    :request_group_id,
    :source_request_event_id,
    :workflow_id,
    :requested,
    :applied,
    :failed,
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

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil
end
