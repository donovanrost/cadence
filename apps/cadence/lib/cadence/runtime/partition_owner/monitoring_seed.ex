defmodule Cadence.Runtime.PartitionOwner.MonitoringSeed do
  @moduledoc """
  On an empty start, seeds each monitoring policy's effective state from the durable latest alarm
  state (director 11-15). A partition starts empty on every activation that changes its runtime
  basis, and when its checkpoint is missing. With every prior at `:normal`, a parameter that went
  back to normal meanwhile never emitted its clear, and its alarm episode stayed active.

  Only active (non-normal) states are seeded, since normal is the default prior, for the plan's
  policies in every spacecraft scope of the mission: a handful of rows. A partition only ever
  evaluates its own evidence's scopes, so another craft's entry is never consulted, and an endpoint
  that carries several spacecraft gets all of theirs. The seed is committed through
  `Store.seed/6`, so a replay from genesis reproduces it.
  """

  import Ecto.Query

  require Logger

  alias Cadence.Repo
  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.SemanticRuntime.{Scope, State, Store}

  @active ~w(watch warning distress critical severe disabled unknown)

  @doc """
  `{:ok, state, writer}`, seeded when the recovered state knows no policy yet; otherwise unchanged.
  """
  def maybe_seed(activation, %PartitionKey{} = key, plan, %State{} = state, writer) do
    if plan.monitoring != [] and state.monitoring_state == %{} do
      entries = entries(activation, plan)

      # Visible in the log, so a live check can see each empty start and what it seeded (qa).
      Logger.info(
        "semantic monitoring seed: #{length(entries)} active alarm state(s) for " <>
          "#{PartitionKey.identifier(key)} (#{activation.mission_id})"
      )

      with {:ok, _result, seeded, next_writer} <-
             Store.seed(activation, key, writer, state, entries, plan) do
        {:ok, seeded, next_writer}
      end
    else
      {:ok, state, writer}
    end
  end

  @doc "The seed: `[{scope, policy_id, effective_state}]`, active states only."
  def entries(activation, plan) do
    case Enum.map(plan.monitoring, & &1.policy_id) do
      [] -> []
      policy_ids -> active(activation.mission_id, policy_ids)
    end
  end

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
