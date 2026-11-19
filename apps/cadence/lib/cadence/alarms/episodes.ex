defmodule Cadence.Alarms.Episodes do
  @moduledoc """
  Opens, escalates and auto-clears alarm episodes from source observations.

  Called inside the transaction that records the source state (catalog monitoring
  transitions, ground-limit evaluations), so episodes can't drift from the state they describe.
  Every observation carries the id of the source record (`ref`). An observation already seen is
  ignored, so replays are idempotent. Observations older than the episode's last observation
  are ignored too.

  | Previous → next | Effect |
  | --- | --- |
  | none → caution/critical | open (`raised`) |
  | alarm → higher severity | `escalated`; an acknowledgement is cleared (the episode is New again) |
  | alarm → lower alarm severity | `deescalated`; the acknowledgement is kept |
  | alarm → normal | `cleared` (auto-clear; it does not wait for an ack) |
  | alarm → same severity | last value / evaluation time only |
  """

  import Ecto.Query

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

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
          optional(:context) => map()
        }

  @doc """
  `observe/2` for use as an `Ecto.Multi.run/3` step. Returns `{:ok, {:changed, mission_id}}` or
  `{:ok, :unchanged}`, so the caller can notify after commit.
  """
  @spec record(module(), observation()) :: {:ok, {:changed, String.t()} | :unchanged}
  def record(repo, observation) do
    case observe(repo, observation) do
      {:ok, :changed} -> {:ok, {:changed, observation.mission_id}}
      {:ok, :unchanged} -> {:ok, :unchanged}
    end
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

  @spec observe(module(), observation()) :: {:ok, :changed | :unchanged}
  def observe(repo, %{level: level} = observation) do
    observation = precise(observation)

    cond do
      seen?(repo, observation) -> {:ok, :unchanged}
      level == :ignore -> {:ok, :unchanged}
      true -> transition(repo, lock_active(repo, observation), observation)
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
      episode_id: Ids.new("alarm_episode"),
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

    episode = repo.insert!(episode)

    event(repo, episode, "raised", observation, %{
      "severity" => severity,
      "source_state" => observation.source_state,
      "value" => value(observation)
    })

    {:ok, :changed}
  end

  defp escalate(repo, episode, observation, next) do
    acked? = not is_nil(episode.acknowledged_at)

    event(repo, episode, "escalated", observation, %{
      "from" => episode.severity,
      "to" => next,
      "source_state" => observation.source_state,
      "value" => value(observation),
      "acknowledgement_cleared" => acked?
    })

    update(repo, episode, observation,
      severity: next,
      peak_severity: max_severity(next, episode.peak_severity),
      acknowledged_at: nil,
      acknowledged_by: nil
    )
  end

  defp deescalate(repo, episode, observation, next) do
    event(repo, episode, "deescalated", observation, %{
      "from" => episode.severity,
      "to" => next,
      "value" => value(observation)
    })

    update(repo, episode, observation, severity: next)
  end

  defp touch(repo, episode, observation) do
    update(repo, episode, observation, [])
    {:ok, :unchanged}
  end

  defp clear(repo, episode, observation, cause) do
    unacknowledged = is_nil(episode.acknowledged_at)

    event(repo, episode, "cleared", observation, %{
      "cause" => Atom.to_string(cause),
      "value" => value(observation),
      "unacknowledged" => unacknowledged
    })

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
  end

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
    repo.insert!(%EpisodeEventRow{
      event_id: Ids.new("alarm_event"),
      episode_id: episode.episode_id,
      organization_id: episode.organization_id,
      mission_id: episode.mission_id,
      kind: kind,
      at: observation.observed_at,
      source_ref: observation.ref,
      payload: payload
    })
  end

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
