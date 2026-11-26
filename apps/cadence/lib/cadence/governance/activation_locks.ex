defmodule Cadence.Governance.ActivationLocks do
  @moduledoc """
  The ONE order for the locks an activation's paths take (director 11-17). Every path that takes
  more than one of them takes them in this order, so no two paths can wait on each other:

    1. the activation policy lock: the organization's `cadence.governance` settings section; the
       organization and its missions share it. Every activation path takes it SHARED
       (`ActivationPolicy.with_stable_policy/2`, `policy/1`): it only needs the policy to stay
       stable, so applies, approvals and executes in an organization's missions don't block each
       other. Only a policy save takes it exclusive. It then takes only the rows a tightening
       suspends (#499: the mission's automation grants FOR UPDATE, after the policy lock, as every
       grant path that takes both does; a grant's use takes no policy lock), so it can't be in a
       cycle; it waits for the readers, and once queued holds back new ones;
    2. the mission's generation lock (`generation/2`);
    3. a change set's own rows: its set row and the mission's ledger head (FOR UPDATE). Only
       `Cadence.Configuration`'s paths lock them (apply, staging, edits), always before the
       configuration lock, and nothing holding the configuration lock locks them;
    4. the mission's configuration lock (`Cadence.Applications.ConfigurationLock`);
    5. then rows: reviewed spacecraft FOR UPDATE, an activation request's model revisions
       FOR SHARE, the request row FOR UPDATE.

  A path may skip a lock it doesn't need, never reorder. The locks are transaction-scoped
  (`pg_advisory_xact_lock`): a lock taken again in the same transaction re-enters, and all of them
  are held to its end.

  Who takes what:
    * execute (`Activations.persist_activation`): policy (approval admission), generation,
      configuration (configuration admission), spacecraft rows;
    * approve (`Control.Activations.approve/4`): policy, configuration (taken explicitly, then
      re-entered by the preflight's admission), then rows: the request's model revisions FOR
      SHARE, the reviewed spacecraft, the request row;
    * a spacecraft review (`Review.request_many`), a configuration save: configuration, then
      rows; never the policy or generation lock;
    * a change-set apply (`Configuration.Submission`): policy and generation FIRST (`acquire/2`),
      then its set row and ledger head, then the configuration lock (its pipeline and generation),
      then the activation record (re-entering policy, generation and configuration).

  Cost: a change-set apply holds the policy lock (shared) for its whole transaction (up to the
  apply's 120 s timeout at fleet scale), so a policy SAVE in its organization waits behind it, and
  approvals and executes queued after that save wait too. Approvals, executes and applies don't
  wait on each other through the policy lock; a mission's approvals and applies still serialize on
  its configuration lock, and its executes and applies on its generation lock.
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

  @doc "The organization's activation policy lock, SHARED, inside the caller's transaction."
  @spec policy(binary()) :: :ok
  def policy(organization_id),
    do: ScopedSettings.section_lock(organization_id, ActivationPolicy.section_id(), :shared)

  @doc "The mission's generation lock, inside the caller's transaction."
  @spec generation(module(), binary()) :: {:ok, :locked} | {:error, term()}
  def generation(repo, mission_id) do
    case SQL.query(repo, "SELECT pg_advisory_xact_lock(hashtext($1))", [mission_id]) do
      {:ok, _result} -> {:ok, :locked}
      {:error, reason} -> {:error, reason}
    end
  end
end
