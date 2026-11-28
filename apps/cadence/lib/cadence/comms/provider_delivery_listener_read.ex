defmodule Cadence.Comms.ProviderDeliveryListenerRead do
  @moduledoc "Scoped, read-only projection of listener bindings and certificate generations."

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @timeout 5_000

  def transport(org, mission, binding) do
    case Repo.query(
           """
           SELECT lifecycle_state, origin, mission_provider_id, configuration
           FROM comms_transports
           WHERE organization_id = $1 AND mission_id = $2 AND transport_id = $3
           ORDER BY version DESC
           LIMIT 1
           """,
           [org, mission, binding],
           timeout: @timeout
         ) do
      {:ok, %{rows: [["active", origin, provider, configuration]]}} ->
        {:ok,
         %{
           origin: origin,
           mission_provider_id: provider,
           configuration: JsonDocument.unwrap_value(configuration)
         }}

      _unavailable ->
        {:error, :wrong_binding}
    end
  end

  def generations(org, mission, provider, binding, ref) do
    case Repo.query(
           """
           SELECT leaf.fingerprint, leaf.generation, leaf.state, leaf.expires_at, leaf.overlap_ends_at
           FROM provider_delivery_credentials AS credential
           JOIN LATERAL (
             SELECT lifecycle_state, provider_account_id, provider_account_grant_id
             FROM mission_providers
             WHERE organization_id = credential.organization_id
               AND mission_id = credential.mission_id
               AND provider_id = credential.provider_id
             ORDER BY version DESC LIMIT 1
           ) AS provider ON provider.lifecycle_state = 'active'
             AND provider.provider_account_id = credential.provider_account_id
             AND provider.provider_account_grant_id = credential.provider_account_grant_id
           JOIN LATERAL (
             SELECT lifecycle_state, mission_id, provider_account_id
             FROM provider_account_grants
             WHERE organization_id = credential.organization_id
               AND provider_account_grant_id = credential.provider_account_grant_id
             ORDER BY version DESC LIMIT 1
           ) AS grant_row ON grant_row.lifecycle_state = 'active'
             AND grant_row.mission_id = credential.mission_id
             AND grant_row.provider_account_id = credential.provider_account_id
           JOIN provider_accounts AS account
             ON account.organization_id = credential.organization_id
             AND account.provider_account_id = credential.provider_account_id
             AND account.lifecycle_state = 'active'
           LEFT JOIN provider_delivery_certificate_generations AS leaf
             ON leaf.credential_ref = credential.credential_ref
             AND (leaf.state IN ('current', 'previous') OR leaf.expires_at > now())
           WHERE credential.organization_id = $1 AND credential.mission_id = $2
             AND credential.provider_id = $3 AND credential.provider_binding_id = $4
             AND credential.credential_ref = $5 AND credential.retired_at IS NULL
           """,
           [org, mission, provider, binding, ref],
           timeout: @timeout
         ) do
      {:ok, %{rows: [_ | _] = rows}} -> {:ok, generations_from_rows(rows)}
      _unavailable -> {:error, :delivery_binding_unavailable}
    end
  end

  defp generations_from_rows(rows) do
    for [fingerprint, generation, state, expiry, cutoff] <- rows, is_binary(fingerprint) do
      %{
        fingerprint: fingerprint,
        generation: generation,
        state: state,
        expires_at: utc(expiry),
        overlap_ends_at: utc(cutoff)
      }
    end
  end

  defp utc(nil), do: nil
  defp utc(naive), do: DateTime.from_naive!(naive, "Etc/UTC")

  def check_binding(org, mission, provider, binding, ref)
      when is_binary(org) and is_binary(mission) and is_binary(provider) and is_binary(binding) and
             is_binary(ref) do
    with {:ok, leaves} <- generations(org, mission, provider, binding, ref) do
      now = DateTime.utc_now()

      if Enum.any?(leaves, &live_generation?(&1, now)),
        do: :ok,
        else: {:error, :delivery_binding_unavailable}
    end
  end

  def check_binding(_org, _mission, _provider, _binding, _ref),
    do: {:error, :delivery_binding_unavailable}

  def live_generation?(%{state: "current", expires_at: expires}, now),
    do: DateTime.after?(expires, now)

  def live_generation?(%{state: "previous", expires_at: expires, overlap_ends_at: cutoff}, now),
    do: DateTime.after?(expires, now) and DateTime.after?(cutoff, now)

  def live_generation?(_generation, _now), do: false
end
