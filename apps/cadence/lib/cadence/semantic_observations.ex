defmodule Cadence.SemanticObservations do
  @moduledoc "Data-plane monitoring evidence and alarm-state projections."

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Catalog.MissionModel.Canonical
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SemanticRuntime.Result

  alias Cadence.SemanticObservations.{
    AlarmAcknowledgementRow,
    AlarmTransitionRow,
    LatestAlarmStateRow,
    MonitoringEvaluationRow
  }

  @spec persist_many([map()]) :: :ok | {:error, term()}
  def persist_many(prepared_results) when is_list(prepared_results) do
    prepared_results
    |> Enum.reduce(Multi.new(), &add_result/2)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  @spec acknowledge(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def acknowledge(organization_id, mission_id, transition_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(transition_id) and
             is_map(actor) do
    case Repo.get_by(AlarmTransitionRow,
           transition_id: transition_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      %AlarmTransitionRow{} ->
        acknowledged_at = opts |> Keyword.get(:at, DateTime.utc_now()) |> normalized_datetime()

        attrs = %{
          acknowledgement_id:
            Canonical.content_id("alarm_acknowledgement", {
              organization_id,
              mission_id,
              transition_id,
              actor,
              acknowledged_at
            }),
          transition_id: transition_id,
          organization_id: organization_id,
          mission_id: mission_id,
          actor: actor,
          note: Keyword.get(opts, :note),
          acknowledged_at: acknowledged_at
        }

        attrs |> AlarmAcknowledgementRow.changeset() |> Repo.insert()

      nil ->
        {:error, :semantic_alarm_transition_not_found}
    end
  end

  @spec list_latest(binary(), binary()) :: [struct()]
  def list_latest(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    LatestAlarmStateRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], desc: row.receipt_time, asc: row.parameter_id)
    |> Repo.all()
  end

  defp add_result(%{semantic_result: %Result{monitoring_results: []}}, multi), do: multi

  defp add_result(%{semantic_result: %Result{} = result} = prepared, multi) do
    updates = Map.new(result.parameter_updates, &{&1.update_id, &1})
    context = semantic_context(prepared)

    result.monitoring_results
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {monitoring_result, index}, acc ->
      update = Map.fetch!(updates, monitoring_result.update_id)
      evaluation_attrs = MonitoringEvaluationRow.attrs(monitoring_result, update, context)

      acc =
        Multi.insert(
          acc,
          {:semantic_monitoring_evaluation, prepared.raw_evidence.evidence_id, index},
          MonitoringEvaluationRow.changeset(evaluation_attrs),
          on_conflict: :nothing
        )

      add_transition(acc, prepared, index, monitoring_result, evaluation_attrs)
    end)
  end

  defp add_result(_prepared, multi), do: multi

  defp add_transition(multi, _prepared, _index, %{transition: nil}, _evaluation_attrs), do: multi

  defp add_transition(multi, prepared, index, result, evaluation_attrs) do
    transition_attrs = AlarmTransitionRow.attrs(evaluation_attrs, result)

    latest_attrs = %{
      organization_id: evaluation_attrs.organization_id,
      mission_id: evaluation_attrs.mission_id,
      spacecraft_id: evaluation_attrs.spacecraft_id,
      parameter_id: evaluation_attrs.parameter_id,
      policy_id: evaluation_attrs.policy_id,
      evaluation_id: evaluation_attrs.evaluation_id,
      transition_id: transition_attrs.transition_id,
      effective_state: evaluation_attrs.effective_state,
      generation_time: evaluation_attrs.generation_time,
      receipt_time: evaluation_attrs.receipt_time
    }

    multi
    |> Multi.insert(
      {:semantic_alarm_transition, prepared.raw_evidence.evidence_id, index},
      AlarmTransitionRow.changeset(transition_attrs),
      on_conflict: :nothing
    )
    |> Multi.insert(
      {:semantic_latest_alarm_state, prepared.raw_evidence.evidence_id, index},
      LatestAlarmStateRow.changeset(latest_attrs),
      on_conflict: latest_alarm_upsert(latest_attrs),
      conflict_target: [:mission_id, :spacecraft_scope_id, :parameter_id, :policy_id],
      allow_stale: true
    )
  end

  defp semantic_context(prepared) do
    monitoring_plan = Map.get(prepared.runtime_spec.runtime_plans, :monitoring)

    %{
      organization_id: prepared.runtime_spec.organization_id,
      mission_id: prepared.runtime_spec.mission_id,
      mission_model_revision_id: prepared.runtime_spec.mission_model_revision_id,
      runtime_plan_id: monitoring_plan.plan_id
    }
  end

  defp latest_alarm_upsert(latest_attrs) do
    from(current in LatestAlarmStateRow,
      update: [
        set: [
          evaluation_id: ^latest_attrs.evaluation_id,
          transition_id: ^latest_attrs.transition_id,
          effective_state: ^latest_attrs.effective_state,
          generation_time: ^latest_attrs.generation_time,
          receipt_time: ^latest_attrs.receipt_time,
          state_document: ^JsonDocument.wrap_value(latest_attrs),
          updated_at: ^DateTime.utc_now()
        ]
      ],
      where:
        fragment(
          "(COALESCE(EXCLUDED.generation_time, EXCLUDED.receipt_time), EXCLUDED.receipt_time, EXCLUDED.transition_id) > (COALESCE(?, ?), ?, ?)",
          current.generation_time,
          current.receipt_time,
          current.receipt_time,
          current.transition_id
        )
    )
  end

  defp normalized_datetime(%DateTime{} = datetime) do
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
