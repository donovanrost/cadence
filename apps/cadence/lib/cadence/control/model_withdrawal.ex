defmodule Cadence.Control.ModelWithdrawal do
  @moduledoc """
  Withdrawing a mission-model approval (E2, #546; design §5) in `ActivationLocks`' order
  (commanding, #546): the activation policy lock (shared), then the mission's configuration lock,
  then the revision row FOR UPDATE (`RevisionDecisions.withdraw/5`). It's the only way in: the
  mission-models facade doesn't expose withdraw, so no caller can skip the locks (commanding).

  An apply (`ConfigurationSelections.check/5`) or an activation approval takes the same revision
  rows FOR SHARE under those locks, so it either sees the withdrawal or finishes before it.
  """

  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationLocks
  alias Cadence.MissionModels.RevisionDecisions
  alias Cadence.Repo

  @doc "See `Cadence.MissionModels.RevisionDecisions.withdraw/5`."
  @spec withdraw(Scope.t(), binary(), binary(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def withdraw(%Scope{} = scope, mission_id, revision_id, reason, opts \\ []) do
    organization_id = scope.organization_id

    Repo.transaction(fn ->
      :ok = ActivationLocks.policy(organization_id)

      organization_id
      |> ConfigurationLock.run(mission_id, fn ->
        RevisionDecisions.withdraw(scope, mission_id, revision_id, reason, opts)
      end)
      |> case do
        {:ok, revision} -> revision
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
