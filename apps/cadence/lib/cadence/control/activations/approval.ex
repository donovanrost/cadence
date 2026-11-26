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
  alias Cadence.Applications.SpacecraftConfiguration.Authors
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.Activations.Preflight
  alias Cadence.Governance.Accountability
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModels
  alias Cadence.Missions

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
         :ok <- Preflight.run(request, opts),
         :ok <- distinct_from_authors(scope, request) do
      ManagementActivations.approve(
        scope,
        request.activation_request_id,
        reason,
        Keyword.delete(opts, :checks)
      )
    end
  end

  # Board #236: where the policy requires an independent approver, the approver may not be ANY
  # author of the spacecraft configuration under review (not only its requester, which
  # Management's decidable checks). Checked against the request's recorded policy, validated
  # current by the preflight.
  #
  # #280 (api-ops' cross-PR item): authors are compared through Governance.Accountability, not by
  # user id alone. A version's `created_by` can be a service identity's id (Drafts.derive writes a
  # change set's applier), which counts as its accountable people; a service nobody is on record
  # for refuses everyone, with `details.service` (#434's spacecraft-list form stays for a review
  # it can't read).
  defp distinct_from_authors(scope, %{metadata: %{"configuration_review" => _}} = request) do
    with true <- separation?(request),
         {:ok, mission} <- Missions.fetch_mission(request.organization_id, request.mission_id),
         {:ok, by_spacecraft} <- Authors.by_spacecraft(mission, request.metadata),
         {:ok, self_ids} <- self_authors(request.organization_id, approver(scope), by_spacecraft) do
      authored = for {id, authors} <- by_spacecraft, Enum.any?(authors, &(&1 in self_ids)), do: id

      if authored == [],
        do: :ok,
        else: {:error, {:activation_approver_authored_content, Enum.sort(authored)}}
    else
      false -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp distinct_from_authors(_scope, _request), do: :ok

  # The author ids (across every reviewed craft) that count as the approver. Each distinct id is
  # checked once, and which ids are service identities is read in ONE query over all of them
  # (#439), so the craft count and the number of people who saved add no queries. Only a service
  # author costs its own accountable-people read.
  # No approver to compare (no person or service on the scope): every author counts, so it fails
  # closed. Approval requires a person before this (Management's decidable).
  defp self_authors(_organization_id, nil, by_spacecraft),
    do: {:ok, by_spacecraft |> Map.values() |> List.flatten() |> Enum.uniq()}

  defp self_authors(organization_id, approver, by_spacecraft) do
    authors = by_spacecraft |> Map.values() |> List.flatten() |> Enum.uniq()

    services =
      for {:service, id} <- Accountability.actors_for_ids(organization_id, authors),
          into: MapSet.new(),
          do: id

    Enum.reduce_while(authors, {:ok, []}, fn author, {:ok, acc} ->
      # As actors_for_ids/2 counts a bare id: the person, and the service when one has that id.
      actors = [{:user, author} | if(author in services, do: [{:service, author}], else: [])]

      case Accountability.separate(organization_id, approver, actors) do
        :ok -> {:cont, {:ok, acc}}
        {:error, {:self, _via}} -> {:cont, {:ok, [author | acc]}}
        {:error, {:unknown, service}} -> {:halt, unknown(service)}
      end
    end)
  end

  defp unknown(service),
    do: {:error, {:activation_approver_authors_unknown, %{service: service}}}

  defp approver(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}}),
    do: {:service, id}

  defp approver(%Scope{user: %{user_id: id}}), do: {:user, id}
  defp approver(_scope), do: nil

  # Fails closed (api-ops): only a request whose recorded policy says separation is OFF ('direct')
  # skips the author check; a missing or malformed policy runs it.
  defp separation?(%{policy_document: %{"separation_of_duties" => false}}), do: false
  defp separation?(_request), do: true

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
