defmodule Cadence.Reads.ActionQueue.SourceKeys do
  @moduledoc """
  The source-specific keys an attention item carries on the wire, beside the shared ones
  (`Cadence.Reads.ActionQueue.AttentionItems.object/2`), for the sources that flatten as is.
  `contact_start` and `provider_change` shape theirs in `AttentionItems`.
  """

  @keys %{
    # DECISIONS #71 / ux U37: telemetry still on disk, not stored. The pass has ended, so the row
    # is always P2; nothing expires it (the journal keeps it) and Cadence retries by itself.
    "contact_settlement" => [
      :reason,
      :failure_kind,
      :failure_message,
      :realized_contact_id,
      :spacecraft_id,
      :ends_at,
      :deadline_at,
      :journal,
      :backlog,
      :expires_at,
      :retry,
      :attempts,
      :next_attempt_at,
      :last_attempt_at,
      :first_failure_kind
    ],
    # 2026-11-12 / ux U38: the mission's runtime hasn't applied its active generation.
    "mission_runtime" => [
      :reason,
      :failure_message,
      :desired_generation,
      :applied_generation,
      :since,
      :activated_at,
      :change_set_id
    ],
    # Director C / ux U41: an approved activation whose apply failed or stalled (Retry apply).
    "activation_apply" => [
      :error_code,
      :error,
      :retryable,
      :activation_request_id,
      :summary,
      :kind,
      :app,
      :spacecraft_ids,
      :spacecraft_count,
      :runtime_not_applied,
      :since,
      :approved_by,
      :approved_at
    ],
    # DECISIONS #83 / ux U47: a contact's ingest buffer filling, or frames lost.
    "ingress_backpressure" => [
      :realized_contact_id,
      :contact_label,
      :ends_at,
      :transport,
      :journal_usage,
      :drops,
      :diagnostics
    ],
    # DECISIONS #88 / ux U49: archive entries that couldn't be indexed (P2, no due time).
    "archive_quarantine" => [
      :realized_contact_id,
      :spacecraft_id,
      :ends_at,
      :error_code,
      :error,
      :counts,
      :stored_without_archive,
      :first_received_at,
      :last_received_at,
      :last_seen_at,
      :actions,
      :last_retry
    ]
  }

  @doc "The item's source-specific keys (`%{}` for a source with none)."
  @spec take(map()) :: map()
  def take(%{source: source} = attention) do
    case Map.fetch(@keys, source) do
      {:ok, keys} -> Map.take(attention, keys)
      :error -> %{}
    end
  end

  def take(_attention), do: %{}
end
