defmodule Cadence.Dashboards.DataLinkResolver.BackfillLifecycleTargets do
  @moduledoc """
  Resolves telemetry backfill lifecycle events and their workflow relationships.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{DataLink, DataLinkInspector}
  alias Cadence.Dashboards.DataLinkResolver.BackfillLifecycleRows
  alias Cadence.Reads.Telemetry, as: TelemetryReads

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(%DataLink{} = link, organization_id, mission_id) do
    link.target_id
    |> TelemetryReads.fetch_backfill_lifecycle_event(
      organization_id: organization_id,
      mission_id: mission_id
    )
    |> case do
      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Telemetry backfill lifecycle event was not found in this mission.",
           []
         )}

      event ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           BackfillLifecycleRows.rows(event, organization_id, mission_id),
           related_links(link, event, organization_id, mission_id)
         )}
    end
  end

  defp related_links(%DataLink{} = link, event, organization_id, mission_id) do
    [
      related_link(
        link,
        :telemetry_point,
        event.point_id || event.observable_id,
        "Telemetry point"
      ),
      late_data_source_link(link, event),
      retry_source_link(link, event),
      correction_source_link(link, event),
      comparison_review_origin_link(link, event)
    ] ++
      group_failure_links(link, event, organization_id, mission_id) ++
      referencing_event_links(link, event, organization_id, mission_id)
  end

  defp retry_source_link(%DataLink{} = link, event) do
    related_link(
      link,
      :telemetry_backfill_lifecycle_event,
      payload_value(event.payload, :retry_source_event_id),
      "Retry source event",
      :source_event
    )
  end

  defp late_data_source_link(%DataLink{} = link, event) do
    related_link(
      link,
      :telemetry_backfill_lifecycle_event,
      payload_value(event.payload, :source_event_id),
      "Late data source event",
      :source_event
    )
  end

  defp correction_source_link(%DataLink{} = link, event) do
    related_link(
      link,
      :telemetry_backfill_lifecycle_event,
      payload_value(event.payload, :corrects_event_id),
      "Correction source event",
      :source_event
    )
  end

  defp comparison_review_origin_link(%DataLink{} = link, event) do
    related_link(
      link,
      :dashboard_lifecycle_event,
      comparison_review_origin_value(event.payload, :request_event_id),
      "Comparison review request",
      :comparison_review_origin
    )
  end

  defp referencing_event_links(%DataLink{} = link, event, organization_id, mission_id) do
    mission_id
    |> TelemetryReads.list_backfill_lifecycle_events(
      organization_id: organization_id,
      limit: 1_000
    )
    |> Enum.reject(&(&1.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id))
    |> Enum.flat_map(fn related_event ->
      related_event
      |> reference_links(event.backfill_lifecycle_event_id)
      |> Enum.map(fn {label, relationship_kind} ->
        related_link(
          link,
          :telemetry_backfill_lifecycle_event,
          related_event.backfill_lifecycle_event_id,
          label,
          relationship_kind
        )
      end)
    end)
  end

  defp reference_links(related_event, source_event_id) do
    [
      reference_link(
        related_event,
        source_event_id,
        :retry_source_event_id,
        "Retry event",
        :retry_event
      ),
      reference_link(
        related_event,
        source_event_id,
        :corrects_event_id,
        correction_reference_label(related_event),
        correction_reference_kind(related_event)
      ),
      reference_link(
        related_event,
        source_event_id,
        :correction_transition_source_event_id,
        "Correction transition event",
        :correction_transition
      ),
      reference_link(
        related_event,
        source_event_id,
        :source_event_id,
        source_reference_label(related_event),
        source_reference_kind(related_event)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp reference_link(related_event, source_event_id, payload_key, label, relationship_kind) do
    case payload_value(related_event.payload, payload_key) do
      ^source_event_id ->
        {"#{label} #{reference_text(related_event)}", relationship_kind}

      _other ->
        nil
    end
  end

  defp source_reference_label(related_event) do
    cond do
      payload_value(related_event.payload, :kind) == "late_data_policy_decision" ->
        "Late data policy event"

      payload_value(related_event.payload, :stage_transition_source) ->
        "Stage transition event"

      true ->
        "Follow-up event"
    end
  end

  defp source_reference_kind(related_event) do
    cond do
      payload_value(related_event.payload, :kind) == "late_data_policy_decision" ->
        :late_data_policy_event

      payload_value(related_event.payload, :stage_transition_source) ->
        :stage_transition_event

      true ->
        :follow_up_event
    end
  end

  defp correction_reference_label(related_event) do
    case payload_value(related_event.payload, :correction_transition_source_event_id) do
      source_event_id when is_binary(source_event_id) and source_event_id != "" ->
        "Correction transition event"

      _other ->
        "Correction request"
    end
  end

  defp correction_reference_kind(related_event) do
    case payload_value(related_event.payload, :correction_transition_source_event_id) do
      source_event_id when is_binary(source_event_id) and source_event_id != "" ->
        :correction_transition

      _other ->
        :correction_request
    end
  end

  defp reference_text(related_event) do
    related_event.point_id || related_event.observable_id ||
      payload_value(related_event.payload, :stage) ||
      related_event.backfill_run_id ||
      related_event.backfill_lifecycle_event_id
  end

  defp group_failure_links(%DataLink{} = link, event, organization_id, mission_id) do
    case payload_value(event.payload, :request_group_id) do
      group_id when is_binary(group_id) and group_id != "" ->
        mission_id
        |> TelemetryReads.list_backfill_lifecycle_events(
          organization_id: organization_id,
          event_type: :backfill_failed,
          limit: 1_000
        )
        |> Enum.filter(&(payload_value(&1.payload, :request_group_id) == group_id))
        |> Enum.sort_by(&failed_group_link_sort_key/1)
        |> Enum.map(fn failed_event ->
          failed_item_label =
            failed_event.point_id || failed_event.observable_id || failed_event.backfill_run_id

          related_link(
            link,
            :telemetry_backfill_lifecycle_event,
            failed_event.backfill_lifecycle_event_id,
            "Failed item #{failed_item_label}"
          )
        end)

      _other ->
        []
    end
  end

  defp failed_group_link_sort_key(event) do
    {payload_value(event.payload, :request_item_index) || 0, event.backfill_run_id}
  end

  defp payload_value(payload, key), do: state_value(payload, key)

  defp comparison_review_origin_value(payload, key) do
    payload
    |> state_value(:comparison_review_origin)
    |> state_value(key)
  end
end
