defmodule Cadence.Governance.ActivationLocks do
  @moduledoc """
  The ONE order for the locks an activation's paths take (director 11-17). Every path that takes
  more than one of them takes them in this order, so no two paths can wait on each other:

    1. the activation policy lock: the organization's `cadence.governance` settings section
       (`ActivationPolicy.with_lock/2`, `policy/1`); the organization and its missions share it;
    2. the mission's generation lock (`generation/2`);
    3. the mission's configuration lock (`Cadence.Applications.ConfigurationLock`);
    4. then rows: reviewed spacecraft FOR UPDATE, an activation request's model revisions
       FOR SHARE, the request row FOR UPDATE.

  A path may skip a lock it doesn't need, never reorder. The locks are transaction-scoped
  (`pg_advisory_xact_lock`): a lock taken again in the same transaction re-enters, and all of them
  are held to its end.

  Who takes what:
    * execute (`Activations.persist_activation`): policy (approval admission), generation,
      configuration (configuration admission), spacecraft rows;
    * approve (`Control.Activations.approve/4`): policy, configuration (the preflight's
      admission), spacecraft rows, model revisions, the request row;
    * a change-set apply (`Configuration.Submission`): policy and generation FIRST (`acquire/2`),
      then its own rows and the configuration lock, then the activation record (re-entering).

  Cost: a change-set apply holds its organization's policy lock for its whole transaction, so the
  organization's approvals and executes wait behind it, and a mission's approvals serialize with
  its change-set applies and configuration saves.
  """
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Platform.ScopedSettings
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  @doc "Takes the policy lock, then the generation lock, inside the caller's transaction."
  @spec acquire(binary(), binary()) :: :ok
  def acquire(organization_id, mission_id) do
    :ok = policy(organization_id)
    {:ok, :locked} = generation(Repo, mission_id)
    :ok
  end

  @doc "The organization's activation policy lock, inside the caller's transaction."
  @spec policy(binary()) :: :ok
  def policy(organization_id),
    do: ScopedSettings.section_lock(organization_id, ActivationPolicy.section_id())

  @doc "The mission's generation lock, inside the caller's transaction."
  @spec generation(module(), binary()) :: {:ok, :locked} | {:error, term()}
  def generation(repo, mission_id) do
    case SQL.query(repo, "SELECT pg_advisory_xact_lock(hashtext($1))", [mission_id]) do
      {:ok, _result} -> {:ok, :locked}
      {:error, reason} -> {:error, reason}
    end
  end
end
