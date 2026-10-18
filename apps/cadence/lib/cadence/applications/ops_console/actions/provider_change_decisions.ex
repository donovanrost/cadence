defmodule Cadence.Applications.OpsConsole.Actions.ProviderChangeDecisions do
  @moduledoc "Host decisions bound to the exact reviewed provider revision and proposal."
  alias Cadence.Auth.Scope
  alias Cadence.Control.Contacts

  @keys ~w(contract_version organization_id mission_id reservation_id change_id provider_revision proposal_hash)
  @actions %{
    "approve-provider-change" => :approve_provider_change,
    "reject-provider-change" => :reject_provider_change,
    "acknowledge-provider-change" => :acknowledge_provider_change
  }

  def decide(%Scope{} = scope, mission, action, params) when is_map_key(@actions, action) do
    with :ok <- exact(params, ~w(provider_reservation_id change_evidence reason)),
         e = params["change_evidence"],
         :ok <- evidence(e),
         :ok <- reason(params["reason"]),
         true <-
           scope.mission_id in [nil, mission] and
             e["organization_id"] == scope.organization_id and e["mission_id"] == mission and
             e["reservation_id"] == params["provider_reservation_id"],
         {:ok, reservation} <-
           Contacts.fetch_provider_reservation(
             scope.organization_id,
             mission,
             e["reservation_id"]
           ),
         {:ok, change} <- Contacts.fetch_provider_change(scope.organization_id, e["change_id"]),
         true <-
           change.mission_id == mission and
             change.provider_reservation_id == reservation.provider_reservation_id and
             change.provider_revision == e["provider_revision"] and
             reservation.provider_revision == e["provider_revision"] and
             change.proposal_hash == e["proposal_hash"],
         {:ok, result} <-
           apply(Contacts, @actions[action], [
             scope,
             change.provider_reservation_change_id,
             change.proposal_hash,
             String.trim(params["reason"])
           ]) do
      updated = if action == "approve-provider-change", do: result.change, else: result

      {:ok,
       %{
         "providerReservationId" => reservation.provider_reservation_id,
         "providerReservationChangeId" => updated.provider_reservation_change_id,
         "providerRevision" => updated.provider_revision,
         "proposalHash" => updated.proposal_hash,
         "lifecycleState" => Atom.to_string(updated.lifecycle_state)
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :stale_provider_change_evidence}
    end
  end

  defp evidence(e) do
    with :ok <- exact(e, @keys),
         true <- e["contract_version"] === 1,
         true <-
           Enum.all?(~w(organization_id mission_id reservation_id change_id), &identifier?(e[&1])),
         v when is_integer(v) and v in 1..2_147_483_647 <- e["provider_revision"],
         h when is_binary(h) and byte_size(h) == 64 <- e["proposal_hash"],
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, h),
         do: :ok,
         else: (_ -> {:error, :invalid_provider_change_evidence})
  end

  defp exact(m, keys) when is_map(m) do
    if MapSet.new(Map.keys(m)) == MapSet.new(keys), do: :ok, else: {:error, :malformed_input}
  end

  defp exact(_, _), do: {:error, :malformed_input}

  defp identifier?(v) when is_binary(v) and byte_size(v) in 1..240,
    do: String.valid?(v) and not Regex.match?(~r/[\x00-\x20\x7f]/, v)

  defp identifier?(_), do: false

  defp reason(v) when is_binary(v) and byte_size(v) in 1..4096 do
    if String.valid?(v) and String.trim(v) != "", do: :ok, else: {:error, :invalid_reason}
  end

  defp reason(_), do: {:error, :invalid_reason}
end
