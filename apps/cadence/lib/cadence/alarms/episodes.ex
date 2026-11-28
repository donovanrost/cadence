defmodule Cadence.Alarms.Episodes do
  @moduledoc """
  Opens, escalates and auto-clears alarm episodes from source observations.

  Called inside the transaction that records the source state (catalog monitoring
  transitions, ground-limit evaluations), so episodes can't drift from the state they describe.
  Every observation carries the id of the source record (`ref`). An observation already seen is
  ignored, so replays are idempotent. Observations older than the episode's last observation
  are ignored too.

  An observation with an `effect_key` (DECISIONS #99: one from a journal frame or a timer) gets
  replay-safe ids instead of `Ids.new`: its episode and event are written insert-or-get, and an id
  already stored means a replay, so the episode change is skipped (no `seen?` read). The stored row
  must be the same effect (`ReplayId.check_replay/4`, on its subject and observation time), else
  `MM_REPLAY_ID_CONFLICT`. Not on the source ref: a transition's id derives from its sample id,
  which includes the evidence id, and a replay that batches the journal differently gets another
  evidence id (11-17 end-to-end test). Observations without a key (ground limits) work as before.

  | Previous → next | Effect |
  | --- | --- |
  | none → caution/critical | open (`raised`) |
  | alarm → higher severity | `escalated`; an acknowledgement is cleared (the episode is New again) |
  | alarm → lower alarm severity | `deescalated`; the acknowledgement is kept |
  | alarm → normal | `cleared` (auto-clear; it does not wait for an ack) |
  | alarm → same severity | last value / evaluation time only |
  | a change of the rules in force while an episode is open | `rule_changed` (the episode is untouched) |

  `rule_changed` (#451 T2): the monitoring evaluator says in a result's metadata that the rules in
  force on a parameter changed (their digest). If an episode of that subject is open and was opened
  before this sample, one event records it: the digests and the ids of the rules then in force. Its
  id is derived from `(episode id, rule ids, from digest, to digest)`, inserted if absent
  (DECISIONS #99), so a replayed batch writes it once and a re-cut batch writes the same one. With no
  open episode nothing is recorded: the new rules simply apply to the next alarm.
  """

  import Ecto.Query

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.Catalog.MissionModel.Canonical
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ReplayId

  @mission_scope "__mission__"
  @rank %{"caution" => 1, "critical" => 2}

  @type level :: :normal | :caution | :critical | :ignore
  @type observation :: %{
          required(:source) => String.t(),
          required(:organization_id) => String.t() | nil,
          required(:mission_id) => String.t(),
          required(:spacecraft_id) => String.t() | nil,
          required(:subject_key) => String.t(),
          required(:parameter_ref) => String.t(),
          required(:level) => level(),
          required(:source_state) => String.t(),
          required(:observed_at) => DateTime.t(),
          required(:evaluated_at) => DateTime.t(),
          required(:ref) => String.t(),
          optional(:point_name) => String.t() | nil,
          optional(:value) => term(),
          optional(:context) => map(),
          optional(:effect_key) => ReplayId.key() | nil
        }

  @doc """
  `observe/2` for use as an `Ecto.Multi.run/3` step. Returns `{:ok, {:changed, mission_id}}` or
  `{:ok, :unchanged}`, so the caller can notify after commit.
  """
  @spec record(module(), observation()) ::
          {:ok, {:changed, String.t()} | :unchanged} | {:error, term()}
  def record(repo, observation) do
    case observe(repo, observation) do
      {:ok, :changed} -> {:ok, {:changed, observation.mission_id}}
      {:ok, :unchanged} -> {:ok, :unchanged}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Records a `rule_changed` event on the subject's open episode (see the module doc). `observation`
  is `Sources.rule_changed/3`'s. Returns what `record/2` does, so the caller notifies after commit.
  """
  @spec rule_changed(module(), map()) ::
          {:ok, {:changed, String.t()} | :unchanged} | {:error, term()}
  def rule_changed(repo, %{rule_change: change} = observation) do
    observation = precise(observation)

    case lock_active(repo, observation) do
      nil ->
        {:ok, :unchanged}

      %EpisodeRow{} = episode ->
        # An episode this very sample opened ran under the new rules from the start.
        if DateTime.compare(episode.opened_at, observation.observed_at) == :lt,
          do: insert_rule_changed(repo, episode, observation, change),
          else: {:ok, :unchanged}
    end
  end

  defp insert_rule_changed(repo, episode, observation, change) do
    id =
      Canonical.content_id(
        "alarm_event",
        {episode.episode_id, "rule_changed", change.rule_ids, change.from, change.to}
      )

    row = %{
      event_id: id,
      episode_id: episode.episode_id,
      organization_id: episode.organization_id,
      mission_id: episode.mission_id,
      kind: "rule_changed",
      at: observation.observed_at,
      source_ref: observation.ref,
      payload: %{
        "from" => change.from,
        "to" => change.to,
        "rule_ids" => change.rule_ids,
        "policy_id" => get_in(observation, [:context, "policy_id"])
      }
    }

    case repo.insert_all(EpisodeEventRow, [row], on_conflict: :nothing, returning: [:event_id]) do
      {1, _rows} -> {:ok, {:changed, episode.mission_id}}
      {0, []} -> {:ok, :unchanged}
    end
  end

  @doc """
  Clears the mission's active catalog-monitoring episodes whose policy is no longer live on their
  spacecraft, with cause `rule_retired` (#451 T3b): a generation dropped the rule for that craft, so
  nothing will evaluate it there again and its episode would stay open for ever. `live?` is
  `fn spacecraft_id | nil, policy_id -> boolean` (`SemanticObservations.LivePolicies.live?/3`).
  Returns the spacecraft of the episodes cleared (`nil` for a mission-wide one).

  The clears run under the episodes' row locks and only touch active ones, so a second run, or a
  second node, finds nothing to clear; the event id derives from the episode and `ref` (the
  generation's) all the same (DECISIONS #99). An episode that records no policy is left alone.
  """
  @spec retire_rules(
          module(),
          String.t(),
          (String.t() | nil, String.t() -> boolean()),
          String.t(),
          DateTime.t()
        ) :: {:ok, [String.t() | nil]}
  def retire_rules(repo, mission_id, live?, ref, at) when is_function(live?, 2) do
    at = usec(at)

    retired =
      EpisodeRow
      |> where(
        [e],
        e.mission_id == ^mission_id and e.source == "catalog_monitoring" and e.state == "active"
      )
      |> lock("FOR UPDATE")
      |> repo.all()
      |> Enum.filter(fn episode ->
        policy = Map.get(episode.context, "policy_id")
        is_binary(policy) and not live?.(episode.spacecraft_id, policy)
      end)

    clear_retired(repo, retired, ref, at)

    {:ok, Enum.map(retired, & &1.spacecraft_id)}
  end

  # The retired episodes cleared in bulk (a statement per 5,000, however many alarms): one `cleared`
  # event each (a deterministic id, a source ref per episode, which is unique in the mission) and
  # the episodes updated, those nobody acknowledged flagged as cleared unacknowledged.
  defp clear_retired(_repo, [], _ref, _at), do: :ok

  defp clear_retired(repo, retired, ref, at) do
    retired
    |> Enum.chunk_every(5_000)
    |> Enum.each(fn chunk ->
      events =
        Enum.map(chunk, fn episode ->
          %{
            event_id:
              Canonical.content_id("alarm_event", {episode.episode_id, "rule_retired", ref}),
            episode_id: episode.episode_id,
            organization_id: episode.organization_id,
            mission_id: episode.mission_id,
            kind: "cleared",
            at: at,
            source_ref: "#{ref}:#{episode.episode_id}",
            payload: %{
              "cause" => "rule_retired",
              "value" => nil,
              "unacknowledged" => is_nil(episode.acknowledged_at)
            }
          }
        end)

      repo.insert_all(EpisodeEventRow, events, on_conflict: :nothing)

      for {unacknowledged?, rows} <- Enum.group_by(chunk, &is_nil(&1.acknowledged_at)) do
        ids = Enum.map(rows, & &1.episode_id)

        repo.update_all(
          from(e in EpisodeRow, where: e.episode_id in ^ids),
          set: [
            state: "cleared",
            cleared_at: at,
            cleared_by_ref: ref,
            cleared_unacknowledged: unacknowledged?,
            last_evaluated_at: at
          ]
        )
      end
    end)

    :ok
  end

  @doc "Applies observations in time order per subject. Returns how many changed an episode."
  @spec observe_many(module(), [observation()]) :: {:ok, non_neg_integer()}
  def observe_many(repo, observations) do
    changed =
      observations
      |> Enum.group_by(&{&1.mission_id, scope(&1.spacecraft_id), &1.source, &1.subject_key})
      |> Enum.flat_map(fn {_subject, group} ->
        Enum.sort_by(group, & &1.observed_at, DateTime)
      end)
      |> Enum.count(&(observe(repo, &1) == {:ok, :changed}))

    {:ok, changed}
  end

  @spec observe(module(), observation()) :: {:ok, :changed | :unchanged} | {:error, term()}
  def observe(repo, %{level: level} = observation) do
    observation = precise(observation)

    cond do
      seen?(repo, observation) -> {:ok, :unchanged}
      level == :ignore and disabled?(observation) -> disabled(repo, observation)
      level == :ignore -> {:ok, :unchanged}
      true -> transition(repo, lock_active(repo, observation), observation)
    end
  end

  # A policy turned off for a spacecraft (an override with `disabled`, #451 T3d) will not evaluate
  # again, so an alarm it raised would stay open for ever: it clears with cause `rule_disabled`.
  # Any other state that raises and clears nothing (`unknown`) still changes no episode.
  defp disabled?(observation), do: to_string(Map.get(observation, :source_state)) == "disabled"

  defp disabled(repo, observation) do
    case lock_active(repo, observation) do
      nil ->
        {:ok, :unchanged}

      %EpisodeRow{} = episode ->
        if DateTime.compare(observation.observed_at, episode.last_observed_at) == :lt,
          do: {:ok, :unchanged},
          else: clear(repo, episode, observation, :rule_disabled)
    end
  end

  @doc """
  Brings ground-limit episodes in line with a rebuilt latest-state projection: observes every
  current state, then clears active ground episodes whose subject is no longer present.
  """
  @spec reconcile_ground(module(), String.t(), String.t() | nil, [observation()]) ::
          {:ok, non_neg_integer()}
  def reconcile_ground(repo, mission_id, spacecraft_id, observations) do
    {:ok, changed} = observe_many(repo, observations)
    present = MapSet.new(observations, &{scope(&1.spacecraft_id), &1.subject_key})
    now = DateTime.utc_now()

    stale =
      EpisodeRow
      |> where(
        [e],
        e.mission_id == ^mission_id and e.source == "ground_limit" and e.state == "active"
      )
      |> spacecraft_filter(spacecraft_id)
      |> lock("FOR UPDATE")
      |> repo.all()
      |> Enum.reject(&MapSet.member?(present, {&1.spacecraft_scope_id, &1.subject_key}))

    Enum.each(stale, &clear(repo, &1, %{ref: nil, value: nil, observed_at: now}, :reconcile))
    {:ok, changed + length(stale)}
  end

  # Episode times are microsecond columns; sources may send coarser timestamps.
  defp precise(observation) do
    observation
    |> Map.update!(:observed_at, &usec/1)
    |> Map.update!(:evaluated_at, &usec/1)
  end

  defp usec(%DateTime{microsecond: {value, _precision}} = time),
    do: %{time | microsecond: {value, 6}}

  @spec scope(String.t() | nil) :: String.t()
  def scope(nil), do: @mission_scope
  def scope(spacecraft_id), do: spacecraft_id

  defp transition(_repo, nil, %{level: :normal}), do: {:ok, :unchanged}
  defp transition(repo, nil, observation), do: open(repo, observation)

  defp transition(repo, %EpisodeRow{} = episode, observation) do
    if DateTime.compare(observation.observed_at, episode.last_observed_at) == :lt do
      {:ok, :unchanged}
    else
      advance(repo, episode, observation)
    end
  end

  defp advance(repo, episode, %{level: :normal} = observation),
    do: clear(repo, episode, observation, :in_limits)

  defp advance(repo, episode, observation) do
    next = Atom.to_string(observation.level)

    case compare(next, episode.severity) do
      :gt -> escalate(repo, episode, observation, next)
      :lt -> deescalate(repo, episode, observation, next)
      :eq -> touch(repo, episode, observation)
    end
  end

  defp open(repo, observation) do
    severity = Atom.to_string(observation.level)

    episode = %EpisodeRow{
      episode_id: effect_id(:alarm_episode, observation, "alarm_episode"),
      organization_id: observation.organization_id,
      mission_id: observation.mission_id,
      spacecraft_id: observation.spacecraft_id,
      spacecraft_scope_id: scope(observation.spacecraft_id),
      source: observation.source,
      subject_key: observation.subject_key,
      parameter_ref: observation.parameter_ref,
      point_name: Map.get(observation, :point_name),
      context: JsonDocument.encode(Map.get(observation, :context, %{})),
      severity: severity,
      peak_severity: severity,
      source_state: observation.source_state,
      state: "active",
      opened_at: observation.observed_at,
      opened_by_ref: observation.ref,
      first_value: value(observation),
      last_value: value(observation),
      last_observed_at: observation.observed_at,
      last_evaluated_at: observation.evaluated_at
    }

    with {:ok, :inserted} <- insert_episode(repo, episode, observation),
         {:ok, :inserted} <-
           event(repo, episode, "raised", observation, %{
             "severity" => severity,
             "source_state" => observation.source_state,
             "value" => value(observation)
           }) do
      {:ok, :changed}
    else
      {:ok, :replayed} -> {:ok, :unchanged}
      {:error, reason} -> {:error, reason}
    end
  end

  defp escalate(repo, episode, observation, next) do
    acked? = not is_nil(episode.acknowledged_at)

    repo
    |> event(episode, "escalated", observation, %{
      "from" => episode.severity,
      "to" => next,
      "source_state" => observation.source_state,
      "value" => value(observation),
      "acknowledgement_cleared" => acked?
    })
    |> unless_replayed(fn ->
      update(repo, episode, observation,
        severity: next,
        peak_severity: max_severity(next, episode.peak_severity),
        acknowledged_at: nil,
        acknowledged_by: nil
      )
    end)
  end

  defp deescalate(repo, episode, observation, next) do
    repo
    |> event(episode, "deescalated", observation, %{
      "from" => episode.severity,
      "to" => next,
      "value" => value(observation)
    })
    |> unless_replayed(fn -> update(repo, episode, observation, severity: next) end)
  end

  defp touch(repo, episode, observation) do
    update(repo, episode, observation, [])
    {:ok, :unchanged}
  end

  defp clear(repo, episode, observation, cause) do
    unacknowledged = is_nil(episode.acknowledged_at)

    repo
    |> event(episode, "cleared", observation, %{
      "cause" => Atom.to_string(cause),
      "value" => value(observation),
      "unacknowledged" => unacknowledged
    })
    |> unless_replayed(fn ->
      episode
      |> Ecto.Changeset.change(
        state: "cleared",
        cleared_at: observation.observed_at,
        cleared_by_ref: observation.ref,
        cleared_unacknowledged: unacknowledged,
        last_value: value(observation) || episode.last_value,
        last_evaluated_at: Map.get(observation, :evaluated_at, observation.observed_at)
      )
      |> repo.update!()

      {:ok, :changed}
    end)
  end

  # The episode change runs only when the event was new; a replayed event means it already ran.
  defp unless_replayed({:ok, :inserted}, change), do: change.()
  defp unless_replayed({:ok, :replayed}, _change), do: {:ok, :unchanged}
  defp unless_replayed({:error, reason}, _change), do: {:error, reason}

  defp update(repo, episode, observation, fields) do
    episode
    |> Ecto.Changeset.change(
      Keyword.merge(
        [
          source_state: observation.source_state,
          last_value: value(observation),
          last_observed_at: observation.observed_at,
          last_evaluated_at: observation.evaluated_at
        ],
        fields
      )
    )
    |> repo.update!()

    {:ok, :changed}
  end

  defp event(repo, episode, kind, observation, payload) do
    row = %EpisodeEventRow{
      event_id:
        Map.get(observation, :event_id) || effect_id(:alarm_event, observation, "alarm_event"),
      episode_id: episode.episode_id,
      organization_id: episode.organization_id,
      mission_id: episode.mission_id,
      kind: kind,
      at: observation.observed_at,
      source_ref: observation.ref,
      payload: payload
    }

    insert_or_get(repo, row, :alarm_event, observation, fn stored ->
      %{subject: repo.get!(EpisodeRow, stored.episode_id).subject_key, at: stored.at}
    end)
  end

  defp insert_episode(repo, episode, observation) do
    insert_or_get(repo, episode, :alarm_episode, observation, fn stored ->
      %{subject: stored.subject_key, at: stored.opened_at}
    end)
  end

  # Unkeyed: a plain insert, as before. Keyed: insert-or-get on the replay-safe id; an id already
  # stored is a replay of the same input (checked on subject and time), so the caller skips its
  # change.
  defp insert_or_get(repo, row, _kind, %{effect_key: nil}, _input_of), do: plain_insert(repo, row)

  defp insert_or_get(repo, %schema{} = row, kind, %{effect_key: %{}} = observation, input_of) do
    fields = row |> Map.from_struct() |> Map.delete(:__meta__) |> with_timestamps(schema)
    [key] = schema.__schema__(:primary_key)
    id = Map.fetch!(fields, key)

    case repo.insert_all(schema, [fields], on_conflict: :nothing, returning: [key]) do
      {1, _rows} ->
        {:ok, :inserted}

      {0, []} ->
        stored = repo.get!(schema, id)
        new = %{subject: observation.subject_key, at: observation.observed_at}

        with :ok <- ReplayId.check_replay(kind, id, input_of.(stored), new),
             do: {:ok, :replayed}
    end
  end

  defp insert_or_get(repo, row, _kind, _observation, _input_of), do: plain_insert(repo, row)

  defp plain_insert(repo, row) do
    repo.insert!(row)
    {:ok, :inserted}
  end

  defp with_timestamps(fields, schema) do
    now = DateTime.utc_now()

    Enum.reduce([:inserted_at, :updated_at], fields, fn field, acc ->
      case {schema.__schema__(:type, field), Map.get(acc, field)} do
        {:utc_datetime_usec, nil} -> Map.put(acc, field, now)
        {:utc_datetime, nil} -> Map.put(acc, field, DateTime.truncate(now, :second))
        _other -> acc
      end
    end)
  end

  defp effect_id(kind, %{effect_key: %{} = key}, _prefix), do: ReplayId.id(kind, key)
  defp effect_id(_kind, _observation, prefix), do: Ids.new(prefix)

  defp seen?(_repo, %{effect_key: %{}}), do: false
  defp seen?(_repo, %{ref: nil}), do: false

  defp seen?(repo, %{mission_id: mission_id, ref: ref}) do
    EpisodeEventRow
    |> where([e], e.mission_id == ^mission_id and e.source_ref == ^ref)
    |> repo.exists?()
  end

  defp lock_active(repo, observation) do
    scope = scope(observation.spacecraft_id)

    EpisodeRow
    |> where(
      [e],
      e.mission_id == ^observation.mission_id and e.spacecraft_scope_id == ^scope and
        e.source == ^observation.source and e.subject_key == ^observation.subject_key and
        e.state == "active"
    )
    |> lock("FOR UPDATE")
    |> repo.one()
  end

  defp spacecraft_filter(query, nil), do: query
  defp spacecraft_filter(query, id), do: where(query, [e], e.spacecraft_id == ^id)

  defp compare(a, b) do
    cond do
      @rank[a] > @rank[b] -> :gt
      @rank[a] < @rank[b] -> :lt
      true -> :eq
    end
  end

  defp max_severity(a, b), do: if(compare(a, b) == :lt, do: b, else: a)

  defp value(%{value: value}) when not is_nil(value), do: JsonDocument.wrap_value(value)
  defp value(_observation), do: nil
end
