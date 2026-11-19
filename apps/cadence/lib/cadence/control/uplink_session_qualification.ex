defmodule Cadence.Control.UplinkSessionQualification do
  @moduledoc """
  Qualifies provider-managed uplink sessions from signed provider attestations (#44 D2,
  `docs/apogee/domain/uplink-path.md`).

  Evidence carries the provider's attestation. It is accepted only when **all** hold:

  - the HMAC-SHA256 signature verifies under the credential of the provider that booked the
    session's contact;
  - `challenge` is the session's current `basis_sha256` (fresh per incarnation, so an old
    attestation can't be replayed);
  - `contact_ref` is that booking's provider contact;
  - `peer` is the connection's peer address in the basis;
  - `purpose` matches the step, the attestation is still valid, and for protocol recovery the
    FARM is unlocked.

  Configuration never qualifies a session: without provider evidence it stays blocked.
  """

  @behaviour Cadence.Runtime.SessionQualification

  alias Cadence.Control.UplinkQualification.Booking

  @impl true
  def verify_fencing(basis, evidence), do: verify(basis, evidence, "fencing")

  @impl true
  def verify_protocol_recovery(basis, _fencing, evidence) do
    with :ok <- verify(basis, evidence, "protocol") do
      if evidence.attestation["farm"] == "unlocked",
        do: :ok,
        else: {:error, :uplink_farm_locked_out}
    end
  end

  @impl true
  def verify_recovery_exchange(_basis, _fencing, _exchange, _evidence),
    do: {:error, :unsupported_takeover}

  @doc "The exact string a provider signs (must match the provider's canonical form)."
  @spec canonical(map()) :: binary()
  def canonical(attestation) do
    ["contact_ref", "challenge", "purpose", "peer", "farm", "valid_until"]
    |> Enum.map_join("\n", &to_string(attestation[&1]))
    |> then(&("cadence-uplink-attestation/v1\n" <> &1))
  end

  defp verify(basis, %{attestation: %{} = attestation} = evidence, purpose) do
    provider_basis = Map.get(basis, :provider, %{})

    with :ok <- same(attestation["purpose"], purpose, :attestation_purpose_mismatch),
         :ok <-
           same(attestation["challenge"], basis.basis_sha256, :attestation_challenge_mismatch),
         :ok <-
           present_same(attestation["peer"], provider_basis[:peer], :attestation_peer_mismatch),
         :ok <- valid_until(attestation, evidence),
         {:ok, booking} <- Booking.for_session(provider_basis),
         :ok <-
           same(
             attestation["contact_ref"],
             booking.provider_contact_ref,
             :attestation_contact_mismatch
           ),
         {:ok, key} <- Booking.credential(booking) do
      signature(attestation, key)
    end
  end

  defp verify(_basis, _evidence, _purpose), do: {:error, :provider_attestation_required}

  defp same(value, value, _reason) when is_binary(value), do: :ok
  defp same(_value, _expected, reason), do: {:error, reason}

  defp present_same(value, expected, reason) when is_binary(expected),
    do: same(value, expected, reason)

  defp present_same(_value, _expected, reason), do: {:error, reason}

  # The gate checks evidence.valid_until (at most 5 minutes ahead); it must be the attested one.
  defp valid_until(attestation, %{valid_until: %DateTime{} = until}) do
    case DateTime.from_iso8601(attestation["valid_until"] || "") do
      {:ok, attested, _offset} ->
        if DateTime.compare(attested, until) == :eq,
          do: :ok,
          else: {:error, :attestation_validity_mismatch}

      _error ->
        {:error, :attestation_validity_mismatch}
    end
  end

  defp valid_until(_attestation, _evidence), do: {:error, :attestation_validity_mismatch}

  defp signature(%{"signature" => signature} = attestation, key) when is_binary(signature) do
    expected =
      :crypto.mac(:hmac, :sha256, key, canonical(attestation)) |> Base.encode16(case: :lower)

    supplied = String.downcase(signature)

    if byte_size(supplied) == byte_size(expected) and :crypto.hash_equals(expected, supplied),
      do: :ok,
      else: {:error, :attestation_signature_invalid}
  end

  defp signature(_attestation, _key), do: {:error, :attestation_signature_invalid}
end
