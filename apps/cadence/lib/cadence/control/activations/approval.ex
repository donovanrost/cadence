defmodule Cadence.Control.Activations.Approval do
  @moduledoc """
  The ONE approve path for activation requests (director 11-17): L10's ActivationRequests, the
  REST ActivationController, the host review and approve_and_execute all reach `approve/4`
  (through `Cadence.Control.Activations.approve/4`). An approval is recorded only for a request
  whose apply could run (`Cadence.Control.Activations.Preflight`), and nothing the preflight checked
  can change before the record: decidable, the preflight and the record run in one transaction
  under the locks in `Cadence.Governance.ActivationLocks`' order.
  """
  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.Activations.Preflight
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModels

  @doc """
  Approves `request_id` only if its apply could run (`preflight/2`); otherwise nothing is recorded
  and the request stays pending. Every approve path goes through here (director 11-17). The
  decision's own checks (`ManagementActivations.decidable/3`: pending, authorized, current
  policy, a distinct approver) run first, so their refusals keep their precedence.
  """
  @spec approve(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, term(), term(), term()} | {:error, term()}
  def approve(%Scope{} = scope, request_id, reason, opts \\ []) do
    # The one lock order (Governance.ActivationLocks): the policy held stable (shared), then the
    # mission's configuration lock, then rows: the request's model revisions FOR SHARE, the
    # preflight's spacecraft rows (its admission re-enters the configuration lock), the request
    # row. All in one transaction, so what the preflight read can't change before the record.
    ActivationPolicy.with_stable_policy(scope.organization_id, fn ->
      approve_decidable(scope, request_id, reason, opts)
    end)
  end

  defp approve_decidable(scope, request_id, reason, opts) do
    with :ok <- ManagementActivations.decidable(scope, request_id, :approved),
         {:ok, request} <- ManagementActivations.fetch(scope, request_id) do
      ConfigurationLock.run(request.organization_id, request.mission_id, fn ->
        approve_locked(scope, request, reason, opts)
      end)
    end
  end

  defp approve_locked(scope, request, reason, opts) do
    with :ok <-
           MissionModels.share_lock_revisions(
             request.organization_id,
             request.mission_id,
             model_revision_ids(request)
           ),
         :ok <- Preflight.run(request, opts) do
      ManagementActivations.approve(
        scope,
        request.activation_request_id,
        reason,
        Keyword.delete(opts, :checks)
      )
    end
  end

  defp model_revision_ids(%{metadata: metadata}) do
    from_fleet = if FleetSnapshot.fleet?(metadata), do: fleet_revision_ids(metadata), else: []

    [get_in(metadata, ["mission_model", "revision_id"]) | from_fleet]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp fleet_revision_ids(metadata) do
    case FleetSnapshot.entries(metadata) do
      {:ok, entries} ->
        Enum.map(entries, fn {_id, entry} -> get_in(entry, ["mission_model", "revision_id"]) end)

      _unreadable ->
        []
    end
  end
end
