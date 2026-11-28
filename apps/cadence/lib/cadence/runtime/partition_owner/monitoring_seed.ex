defmodule Cadence.Runtime.PartitionOwner.MonitoringSeed do
  @moduledoc """
  Seeds a monitoring policy's effective state from the durable latest alarm state when the
  recovered state has none for it (director 11-15): a partition's state starts without a policy
  when its checkpoint is missing, and, since a revision keeps the state of every policy it didn't
  change (#443, `Carry`), for each policy the revision added or changed. With every prior at
  `:normal`, a parameter that went back to normal meanwhile never emitted its clear, and its alarm
  episode stayed active.

  Only active (non-normal) states are seeded, since normal is the default prior, for the plan's
  policies in every spacecraft scope of the mission: a handful of rows. A partition only ever
  evaluates its own evidence's scopes, so another craft's entry is never consulted, and an endpoint
  that carries several spacecraft gets all of theirs. The seed is applied with
  `SemanticRuntime.seed_monitoring/2` and held by the partition's next snapshot.

  `semantic_latest_alarm_states` is a projection, written AFTER the batch is evaluated: the ingress
  persistence projector persists each processed batch (`Runtime.Persistence`, then
  `SemanticObservations.persist_many/1`, which writes the transition, the latest state and the
  episode in one transaction). So a seed taken right after a basis change can be one step stale
  (api-ops), and both cases are benign:
  - stale-active (the clear hasn't been projected yet): the first normal sample emits a second
    `→ normal`, and the episode is already cleared, so it's absorbed;
  - stale-normal (the raise hasn't been projected yet): today's pre-seed behaviour, so the next
    violation raises again, and Episodes treats a same-severity raise as a value update.
  """

  import Ecto.Query

  require Logger

  alias Cadence.Repo
  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{Scope, State}

  @active ~w(watch warning distress critical severe disabled unknown)

  @doc """
  `{:ok, state}`, seeded for the policies the recovered state has no entry for; unchanged when it
  has one for every policy.
  """
  def maybe_seed(activation, %PartitionKey{} = key, plan, %State{} = state) do
    unseeded = for %{policy_id: id} <- plan.monitoring, not seeded?(state, id), do: id

    if unseeded != [] do
      entries = active(activation.mission_id, unseeded)

      # Visible in the log, so a live check can see each empty start and what it seeded (qa).
      Logger.info(
        "semantic monitoring seed: #{length(entries)} active alarm state(s) for " <>
          "#{PartitionKey.identifier(key)} (#{activation.mission_id})"
      )

      {:ok, SemanticRuntime.seed_monitoring(state, Enum.sort(entries))}
    else
      {:ok, state}
    end
  end

  @doc "The seed: `[{scope, policy_id, effective_state}]`, active states only."
  def entries(activation, plan),
    do: active(activation.mission_id, Enum.map(plan.monitoring, & &1.policy_id))

  # Some spacecraft scope already holds state for the policy: it was carried or evaluated.
  defp seeded?(%State{monitoring_state: monitoring_state}, policy_id),
    do: Enum.any?(monitoring_state, fn {{_scope, id}, _state} -> id == policy_id end)

  defp active(_mission_id, []), do: []

  defp active(mission_id, policy_ids) do
    from(row in LatestAlarmStateRow,
      where:
        row.mission_id == ^mission_id and row.policy_id in ^policy_ids and
          row.effective_state in ^@active,
      select: {row.mission_id, row.spacecraft_id, row.policy_id, row.effective_state}
    )
    |> Repo.all()
    |> Enum.map(fn {mission_id, spacecraft_id, policy_id, effective_state} ->
      {Scope.new(mission_id, spacecraft_id), policy_id, String.to_existing_atom(effective_state)}
    end)
  end
end
