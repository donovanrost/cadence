defmodule Cadence.Control.ConfigurationRollback do
  @moduledoc """
  Rolling a mission's configuration back to an earlier revision
  (docs/apogee/domain/change-sets.md §8; planning in `Cadence.Configuration.Rollback`).

  `preview/3` shows what it would do, checked like any change. `stage/3` stages it as one change
  in a new change set, which then goes through checks, review and apply like any set and applies
  as a `rollback` revision. Kinds do the inverse writes, so a framing rollback produces its
  runtime generation (#45) and the same HOLDs; values changed outside change sets since the
  target become a HOLD to acknowledge.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Configuration.{Access, Preview, Rollback, Staging}
  alias Cadence.Platform.ScopedReadUpdates

  @doc """
  `{target, head, reverts, summary, ops: [%{kind, entity_id, action}], outside, preview}`;
  `preview` is nil when there's nothing to revert. Nothing is written.
  """
  @spec preview(Scope.t(), String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def preview(%Scope{} = scope, mission_id, target) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :rollback),
         {:ok, plan} <- Rollback.plan(mission.organization_id, mission.mission_id, target),
         {:ok, preview} <- checks(mission, plan) do
      {:ok, plan |> view() |> Map.put(:preview, preview)}
    end
  end

  @doc """
  Stages the rollback. Staging decides under the change-set lock that the set is empty
  (`:change_set_open` otherwise) and keeps other changes out of it afterwards.
  """
  @spec stage(Scope.t(), String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def stage(%Scope{} = scope, mission_id, target) do
    with {:ok, mission} <- Access.authorize(scope, mission_id, :rollback),
         {:ok, plan} <- Rollback.plan(mission.organization_id, mission.mission_id, target),
         :ok <- something_to_revert(plan),
         {:ok, result} <-
           Staging.stage(
             mission.organization_id,
             mission.mission_id,
             plan.head,
             Access.actor(scope),
             %{summary: plan.summary, source: source(plan)},
             plan.ops
           ) do
      ScopedReadUpdates.publish(
        :configuration_changed,
        mission.organization_id,
        mission.mission_id
      )

      {:ok, result}
    end
  end

  defp checks(_mission, %{ops: []}), do: {:ok, nil}

  defp checks(mission, plan) do
    with {:ok, prepared} <-
           Staging.prepare_ops(mission.organization_id, mission.mission_id, plan.ops) do
      ops = Enum.map(prepared, &Map.put(&1, :source, source(plan)))
      Preview.run(mission.organization_id, mission.mission_id, plan.head, ops)
    end
  end

  defp view(plan) do
    %{
      target: plan.target,
      head: plan.head,
      reverts: plan.reverts,
      summary: plan.summary,
      ops: Enum.map(plan.ops, &Map.take(&1, [:kind, :entity_id, :action])),
      outside: plan.outside
    }
  end

  defp source(plan) do
    %{
      "rollback" => %{
        "to" => plan.target,
        "reverts" => plan.reverts,
        "outside" => Enum.map(plan.outside, &%{"kind" => &1.kind, "entity_id" => &1.entity_id})
      }
    }
  end

  defp something_to_revert(%{ops: []}), do: {:error, :nothing_to_roll_back}
  defp something_to_revert(_plan), do: :ok
end
