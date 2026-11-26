defmodule Cadence.SemanticObservations do
  @moduledoc """
  Durable alarm transitions, their supporting evaluations, and alarm-state projections.

  Routine evaluations remain part of semantic execution but do not require a
  separate relational write. A transition's evaluation, transition, and latest
  state are committed atomically so alarm evidence remains available on retry.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Cadence.Alarms.{Episodes, Notify, Sources}
  alias Cadence.Catalog.MissionModel.Canonical
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ReplayId
  alias Cadence.Repo
  alias Cadence.SemanticRuntime.Result

  alias Cadence.SemanticObservations.{
    AlarmAcknowledgementRow,
    AlarmTransitionRow,
    FleetAlarms,
    LatestAlarmStateRow,
    MonitoringEvaluationRow
  }

  @spec persist_many([map()]) :: :ok | {:error, term()}
  def persist_many(prepared_results) when is_list(prepared_results) do
    prepared_results
    |> Enum.reduce({Multi.new(), []}, &add_result/2)
    |> persist_transitions()
  end

  defp persist_transitions({_transitions, []}), do: :ok

  defp persist_transitions({transitions, evaluations}) do
    evaluations
    |> evaluation_multi(transitions)
    |> Multi.run(:fleet_alarm_summaries, fn repo, _changes ->
      refresh_fleet_alarms(repo, evaluations)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} ->
        notify_alarm_changes(changes)
        :ok

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  # The fleet summary of every spacecraft this batch transitioned, once each (#871).
  defp refresh_fleet_alarms(repo, evaluations) do
    evaluations
    |> Enum.map(
      &{Ecto.Changeset.get_field(&1, :organization_id), Ecto.Changeset.get_field(&1, :mission_id),
       Ecto.Changeset.get_field(&1, :spacecraft_id)}
    )
    |> Enum.reject(fn {organization_id, _mission, spacecraft} ->
      is_nil(organization_id) or is_nil(spacecraft)
    end)
    |> Enum.uniq()
    |> Enum.group_by(fn {org, mission, _craft} -> {org, mission} end, &elem(&1, 2))
    |> Enum.each(fn {{organization_id, mission_id}, spacecraft_ids} ->
      FleetAlarms.refresh(repo, organization_id, mission_id, spacecraft_ids)
    end)

    {:ok, :refreshed}
  end

  defp notify_alarm_changes(changes) do
    changes
    |> Enum.flat_map(fn
      {{:alarm_episode, _evidence, _index}, {:changed, mission_id}} -> [mission_id]
      _other -> []
    end)
    |> Notify.missions_changed()
  end

  defp evaluation_multi(evaluations, transitions) do
    Multi.new()
    |> Multi.run(:semantic_monitoring_evaluations, fn repo, _changes ->
      persist_evaluations(repo, Enum.reverse(evaluations))
    end)
    |> Multi.append(transitions)
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

  defp add_result(%{semantic_result: %Result{} = result} = prepared, accumulator) do
    transitions = Enum.reject(result.monitoring_results, &is_nil(&1.transition))
    add_transitions(prepared, transitions, accumulator)
  end

  defp add_result(_prepared, accumulator), do: accumulator

  defp add_transitions(_prepared, [], accumulator), do: accumulator

  defp add_transitions(%{semantic_result: result} = prepared, transitions, accumulator) do
    updates = Map.new(result.parameter_updates, &{&1.update_id, &1})
    context = semantic_context(prepared)
    rules = Map.get(prepared, :alarm_rules, %{})

    # Replay-safe effect keys (DECISIONS #99): numbered per input (journal frame or timer) over ALL
    # of its monitoring evaluations (every monitored update x policy, emitted whatever the state),
    # not over its transitions. Which of them transition depends on the monitoring state recovery
    # restored (the seed restores only non-normal states), so a replay can derive a subset; the
    # evaluations' order depends only on the input, so each transition keeps its index.
    ordinals = Map.get(prepared, :effect_ordinals, %{})

    evaluation_keys =
      result.monitoring_results
      |> ReplayId.number(&effect_source(Map.fetch!(updates, &1.update_id)), ordinals)
      |> Map.new(fn {evaluation, key} -> {{evaluation.update_id, evaluation.policy_id}, key} end)

    keys = Enum.map(transitions, &Map.get(evaluation_keys, {&1.update_id, &1.policy_id}))

    transitions
    |> Enum.zip(keys)
    |> Enum.with_index()
    |> Enum.reduce(accumulator, fn {{monitoring_result, effect_key}, index},
                                   {multi, evaluations} ->
      update = Map.fetch!(updates, monitoring_result.update_id)
      evaluation_attrs = MonitoringEvaluationRow.attrs(monitoring_result, update, context)
      match = Map.get(rules, {monitoring_result.policy_id, monitoring_result.update_id})

      {add_transition(
         multi,
         prepared,
         index,
         monitoring_result,
         evaluation_attrs,
         {update, match, effect_key}
       ), [MonitoringEvaluationRow.changeset(evaluation_attrs) | evaluations]}
    end)
  end

  # Flight events: `prepared.alarm_rules` (`SemanticRuntime.AlarmRules`, built by the partition
  # owner) says which rule opened or escalated each alarm transition. Missing (an older prepared
  # result, a recovered commit of another generation): the episode classifies by value instead.

  defp persist_evaluations(repo, changesets) do
    with {:ok, rows} <- evaluation_rows(changesets) do
      rows
      |> Enum.reverse()
      |> Enum.chunk_every(1_000)
      |> Enum.each(
        &repo.insert_all(MonitoringEvaluationRow, &1,
          on_conflict: :nothing,
          cache_statement: false
        )
      )

      {:ok, length(rows)}
    end
  end

  defp evaluation_rows(changesets) do
    now = DateTime.utc_now()

    Enum.reduce_while(changesets, {:ok, []}, fn changeset, {:ok, rows} ->
      case Ecto.Changeset.apply_action(changeset, :insert) do
        {:ok, row} ->
          attrs = row |> Map.from_struct() |> Map.delete(:__meta__) |> Map.put(:inserted_at, now)
          {:cont, {:ok, [attrs | rows]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp add_transition(
         multi,
         prepared,
         index,
         result,
         evaluation_attrs,
         {update, match, effect_key}
       ) do
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
    |> Multi.run({:alarm_episode, prepared.raw_evidence.evidence_id, index}, fn repo, _changes ->
      observation =
        evaluation_attrs
        |> Sources.catalog(update, transition_attrs.transition_id, match)
        |> Map.put(:effect_key, effect_key)

      Episodes.record(repo, observation)
    end)
  end

  defp effect_source(%{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, :effect_source, Map.get(metadata, "effect_source"))

  defp effect_source(_update), do: nil

  defp semantic_context(%{observation_context: context}) when is_map(context), do: context

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
