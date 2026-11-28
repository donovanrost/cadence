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
  alias Cadence.SemanticRuntime.{AlarmLevel, Result}

  alias Cadence.SemanticObservations.{
    AlarmAcknowledgementRow,
    AlarmTransitionRow,
    FleetAlarms,
    LatestAlarmStateRow,
    MonitoringEvaluationRow
  }

  @spec persist_many([map()]) :: :ok | {:error, term()}
  def persist_many(prepared_results) when is_list(prepared_results) do
    rule_changes = Enum.flat_map(prepared_results, &rule_changes/1)

    prepared_results
    |> Enum.reduce({Multi.new(), [], []}, &add_result/2)
    |> persist_transitions(rule_changes)
  end

  defp persist_transitions({_operations, [], []}, []), do: :ok

  # A batch with a change of rules but no transition: only the episode events.
  defp persist_transitions({_operations, [], []}, rule_changes) do
    Multi.new() |> add_rule_changes(rule_changes) |> run_transaction()
  end

  defp persist_transitions({operations, evaluations, transition_changesets}, rule_changes) do
    evaluations
    |> evaluation_multi(transition_changesets, operations)
    |> Multi.run(:fleet_alarm_summaries, fn repo, _changes ->
      refresh_fleet_alarms(repo, evaluations)
    end)
    |> add_rule_changes(rule_changes)
    |> run_transaction()
  end

  defp run_transaction(multi) do
    multi
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
    |> then(&FleetAlarms.refresh_batch(repo, &1))

    {:ok, :refreshed}
  end

  # The `rule_changed` of every monitoring result (the rules in force on its parameter changed,
  # #451 T2) as an episode observation, in the batch's order. A result that opened an alarm from
  # normal is left out: its episode ran under the new rules from its first sample.
  defp rule_changes(%{semantic_result: %Result{} = result} = prepared) do
    updates = Map.new(result.parameter_updates, &{&1.update_id, &1})
    context = semantic_context(prepared)
    evidence_id = prepared.raw_evidence.evidence_id

    for {monitoring, index} <- Enum.with_index(result.monitoring_results),
        %{} = change <- [Map.get(monitoring.metadata || %{}, :rule_changed)],
        not opened_here?(monitoring),
        update = Map.fetch!(updates, monitoring.update_id) do
      attrs = MonitoringEvaluationRow.attrs(monitoring, update, context)
      {{:alarm_rule_changed, evidence_id, index}, Sources.rule_changed(attrs, update, change)}
    end
  end

  defp rule_changes(_prepared), do: []

  defp opened_here?(%{transition: %{from: :normal}}), do: true
  defp opened_here?(_monitoring), do: false

  defp add_rule_changes(multi, rule_changes) do
    Enum.reduce(rule_changes, multi, fn {key, observation}, acc ->
      Multi.run(acc, {:alarm_episode, key, observation.ref}, fn repo, _changes ->
        Episodes.rule_changed(repo, observation)
      end)
    end)
  end

  @doc """
  A generation's rules no longer include some policies (`live_policy_ids` are the ones it keeps;
  #451 T3b): their open episodes clear with cause `rule_retired`, their latest alarm states go, and
  the fleet summaries of the spacecraft they were on are recomputed, in one transaction. One call
  per generation and mission, however many spacecraft are affected; idempotent, so a second node
  or a repeat writes nothing more. `ref` names the generation (it keys the episode events), `at`
  is when it was applied, and `generation` is its number.

  The same transaction records the generation's policies (`semantic_live_policies`), so a batch
  persisted later but evaluated under an OLDER generation cannot bring a retired policy's state
  back (`drop_retired/2`). A run for a generation older than the recorded one does nothing.
  """
  @spec retire_rules(binary(), binary(), [binary()], binary(), DateTime.t(), pos_integer()) ::
          {:ok, %{episodes: non_neg_integer(), states: non_neg_integer()}} | {:error, term()}
  def retire_rules(organization_id, mission_id, live_policy_ids, ref, at, generation) do
    Repo.transaction(fn ->
      if record_live_policies(Repo, organization_id, mission_id, live_policy_ids, generation) do
        {:ok, episodes} = Episodes.retire_rules(Repo, mission_id, live_policy_ids, ref, at)
        states = retire_states(Repo, organization_id, mission_id, live_policy_ids)

        :ok =
          FleetAlarms.refresh(Repo, organization_id, mission_id, Enum.uniq(episodes ++ states))

        %{episodes: length(episodes), states: length(states)}
      else
        %{episodes: 0, states: 0}
      end
    end)
    |> tap(fn
      {:ok, %{episodes: count}} when count > 0 -> Notify.missions_changed([mission_id])
      _other -> :ok
    end)
  end

  # True when this generation is the newest recorded (or the same one again): the row only moves
  # forward.
  defp record_live_policies(repo, organization_id, mission_id, policy_ids, generation) do
    now = DateTime.utc_now()

    {count, _rows} =
      repo.insert_all(
        "semantic_live_policies",
        [
          %{
            organization_id: organization_id,
            mission_id: mission_id,
            generation: generation,
            policy_ids: policy_ids,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict:
          from(live in "semantic_live_policies",
            where: live.generation <= ^generation,
            update: [set: [generation: ^generation, policy_ids: ^policy_ids, updated_at: ^now]]
          ),
        conflict_target: [:organization_id, :mission_id]
      )

    count == 1
  end

  # The spacecraft of the latest states of the mission's policies no generation keeps.
  defp retire_states(repo, organization_id, mission_id, live_policy_ids) do
    {_count, spacecraft} =
      repo.delete_all(
        from(row in LatestAlarmStateRow,
          where:
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.policy_id not in ^live_policy_ids,
          select: row.spacecraft_id
        )
      )

    spacecraft
  end

  defp notify_alarm_changes(changes) do
    changes
    |> Enum.flat_map(fn
      {{:alarm_episode, _evidence, _index}, {:changed, mission_id}} -> [mission_id]
      _other -> []
    end)
    |> Notify.missions_changed()
  end

  defp evaluation_multi(evaluations, transition_changesets, operations) do
    Multi.new()
    |> Multi.run(:semantic_monitoring_evaluations, fn repo, _changes ->
      persist_evaluations(repo, Enum.reverse(evaluations))
    end)
    |> Multi.run(:semantic_alarm_transitions, fn repo, _changes ->
      persist_alarm_transitions(repo, Enum.reverse(transition_changesets))
    end)
    |> Multi.append(operations)
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

  @doc """
  One spacecraft's latest live alarm states: a row per (parameter, policy) that has changed state
  (a state is written on a transition only, so a parameter that never left normal has none).
  """
  @spec list_for_spacecraft(binary(), binary(), binary()) :: [struct()]
  def list_for_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    LatestAlarmStateRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.spacecraft_scope_id == ^spacecraft_id
    )
    |> Repo.all()
  end

  @doc """
  The alarm level of each parameter of one spacecraft that has a state: `%{parameter_id =>
  :critical | :caution | :nominal}`, the worst over the parameter's policies. A parameter that
  never changed state has none (see `Reads.PointLimitState`), and a state that raises or clears
  nothing (`disabled`, `unknown`) is left out.
  """
  @spec levels_for_spacecraft(binary(), binary(), binary()) :: %{
          binary() => :critical | :caution | :nominal
        }
  def levels_for_spacecraft(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> list_for_spacecraft(mission_id, spacecraft_id)
    |> Enum.flat_map(fn row ->
      case AlarmLevel.level(row.effective_state) do
        :critical -> [{row.parameter_id, 0, :critical}]
        :caution -> [{row.parameter_id, 1, :caution}]
        :normal -> [{row.parameter_id, 2, :nominal}]
        :ignore -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {parameter, levels} ->
      {parameter, levels |> Enum.min_by(&elem(&1, 1)) |> elem(2)}
    end)
  end

  defp add_result(%{semantic_result: %Result{} = result} = prepared, accumulator) do
    transitions = Enum.reject(result.monitoring_results, &is_nil(&1.transition))
    add_transitions(prepared, drop_retired(prepared, transitions), accumulator)
  end

  defp add_result(_prepared, accumulator), do: accumulator

  # A batch evaluated under an OLDER generation can reach the projector after a newer generation
  # retired one of its policies (`retire_rules/6` already ran): its transition would bring the
  # policy's latest state back (a phantom alarm on Fleet) or touch a cleared episode's story
  # (#451 T3b). Such a transition is not persisted: the mission's recorded generation is newer than
  # the batch's and does not keep the policy. Nothing is asked for a batch with no transition, and
  # nothing is dropped for a batch of the recorded generation or a newer one (a generation's own
  # new policies arrive before its retirement has recorded it).
  defp drop_retired(_prepared, []), do: []

  defp drop_retired(prepared, transitions) do
    case semantic_context(prepared) do
      %{organization_id: organization_id, mission_id: mission_id, generation: generation}
      when is_binary(organization_id) and is_integer(generation) ->
        policies = transitions |> Enum.map(& &1.policy_id) |> Enum.uniq()
        kept = kept_policies(organization_id, mission_id, generation, policies)
        if kept, do: Enum.filter(transitions, &(&1.policy_id in kept)), else: transitions

      _no_generation ->
        transitions
    end
  end

  # Of `policies`, the ones the mission's recorded generation keeps, when that generation is newer
  # than `generation`; nil when it is not (nothing to drop).
  defp kept_policies(organization_id, mission_id, generation, policies) do
    Repo.one(
      from(live in "semantic_live_policies",
        where:
          live.organization_id == ^organization_id and live.mission_id == ^mission_id and
            live.generation > ^generation,
        select:
          fragment(
            "ARRAY(SELECT p FROM unnest(?::text[]) p WHERE p = ANY(?))",
            ^policies,
            live.policy_ids
          )
      )
    )
  end

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
                                   {multi, evaluations, transition_changesets} ->
      update = Map.fetch!(updates, monitoring_result.update_id)
      evaluation_attrs = MonitoringEvaluationRow.attrs(monitoring_result, update, context)
      match = Map.get(rules, {monitoring_result.policy_id, monitoring_result.update_id})

      {operations, transition_changeset} =
        add_transition(
          multi,
          prepared,
          index,
          monitoring_result,
          evaluation_attrs,
          {update, match, effect_key}
        )

      {operations, [MonitoringEvaluationRow.changeset(evaluation_attrs) | evaluations],
       [transition_changeset | transition_changesets]}
    end)
  end

  # Flight events: `prepared.alarm_rules` (`SemanticRuntime.AlarmRules`, built by the partition
  # owner) says which rule opened or escalated each alarm transition. Missing (an older prepared
  # result, a recovered commit of another generation): the episode classifies by value instead.

  defp persist_evaluations(repo, changesets) do
    with {:ok, rows} <- validated_rows(changesets) do
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

  defp persist_alarm_transitions(repo, changesets) do
    with {:ok, rows} <- validated_rows(changesets) do
      rows
      |> Enum.reverse()
      |> Enum.chunk_every(1_000)
      |> Enum.each(
        &repo.insert_all(AlarmTransitionRow, &1,
          on_conflict: :nothing,
          cache_statement: false
        )
      )

      {:ok, length(rows)}
    end
  end

  defp validated_rows(changesets) do
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

    operations =
      multi
      |> Multi.insert(
        {:semantic_latest_alarm_state, prepared.raw_evidence.evidence_id, index},
        LatestAlarmStateRow.changeset(latest_attrs),
        on_conflict: latest_alarm_upsert(latest_attrs),
        conflict_target: [:mission_id, :spacecraft_scope_id, :parameter_id, :policy_id],
        allow_stale: true
      )
      |> Multi.run({:alarm_episode, prepared.raw_evidence.evidence_id, index}, fn repo,
                                                                                  _changes ->
        observation =
          evaluation_attrs
          |> Sources.catalog(update, transition_attrs.transition_id, match)
          |> Map.put(:effect_key, effect_key)

        Episodes.record(repo, observation)
      end)

    {operations, AlarmTransitionRow.changeset(transition_attrs)}
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
