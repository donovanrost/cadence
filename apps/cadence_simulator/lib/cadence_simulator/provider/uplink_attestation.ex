defmodule CadenceSimulator.Provider.UplinkAttestation do
  @moduledoc """
  Signed uplink-session attestations (#44 D2).

  Cadence challenges with its session's fresh basis hash; the provider answers for one contact
  whose uplink leg is included and whose COP-1 peer is connected, naming that peer's own socket
  address (`peer`) and its FARM state (`farm`). The signature is HMAC-SHA256 under the provider
  API credential over `canonical/1`, so only a holder of the credential can produce it and it
  binds the challenge, contact, purpose, connection and validity.
  """

  alias CadenceSimulator.COP1.LoopbackPeer
  alias CadenceSimulator.Provider.{Contacts, Orchestrator}

  @purposes ["fencing", "protocol"]
  @validity_seconds 240

  @spec attest(map(), binary(), map(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def attest(run, contact_id, params, key, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    session = Keyword.get(opts, :session, &Orchestrator.uplink_session/1)

    with {:ok, challenge, purpose} <- request(params),
         {:ok, contact} <- Contacts.fetch(run, contact_id),
         :ok <- uplink_included(contact),
         {:ok, peer} <- connected_peer(session.(contact_id)) do
      attestation = %{
        "contact_ref" => contact_id,
        "challenge" => challenge,
        "purpose" => purpose,
        "peer" => peer.local_address,
        "farm" => farm(peer),
        "valid_until" =>
          now
          |> DateTime.add(@validity_seconds, :second)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()
      }

      {:ok, Map.put(attestation, "signature", sign(attestation, key))}
    end
  end

  @doc "The exact string the signature covers; Cadence rebuilds it to verify."
  @spec canonical(map()) :: binary()
  def canonical(attestation) do
    Enum.map_join(
      ["contact_ref", "challenge", "purpose", "peer", "farm", "valid_until"],
      "\n",
      &to_string(attestation[&1])
    )
    |> then(&("cadence-uplink-attestation/v1\n" <> &1))
  end

  defp sign(attestation, key),
    do:
      :crypto.mac(:hmac, :sha256, key || "", canonical(attestation))
      |> Base.encode16(case: :lower)

  defp request(%{"challenge" => challenge, "purpose" => purpose})
       when is_binary(challenge) and byte_size(challenge) in 16..128 and purpose in @purposes,
       do: {:ok, challenge, purpose}

  defp request(_params),
    do:
      {:error, {:invalid, "challenge (16-128 chars) and purpose (fencing|protocol) are required"}}

  defp uplink_included(%{"status" => "active", "uplink" => %{"status" => "included"}}), do: :ok

  defp uplink_included(_contact),
    do: {:error, {:conflict, "contact has no active included uplink leg"}}

  defp connected_peer(pid) when is_pid(pid) do
    case LoopbackPeer.snapshot(pid) do
      %{connected?: true, local_address: address} = peer when is_binary(address) -> {:ok, peer}
      _not_connected -> {:error, {:conflict, "uplink session is not connected"}}
    end
  catch
    :exit, _ -> {:error, {:conflict, "uplink session is not connected"}}
  end

  defp connected_peer(_none), do: {:error, {:conflict, "uplink session is not connected"}}

  defp farm(%{farm_states: states}) do
    if Enum.any?(states, fn {_vcid, farm} -> farm.state == :lockout end),
      do: "lockout",
      else: "unlocked"
  end
end
