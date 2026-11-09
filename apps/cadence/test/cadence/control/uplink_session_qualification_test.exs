defmodule Cadence.Control.UplinkSessionQualificationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.UplinkSessionQualification, as: Policy
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Runtime.SessionReadiness
  alias Ecto.Adapters.SQL.Sandbox

  @key "provider-secret"
  @peer "127.0.0.1:50123"

  setup do
    previous = Application.get_env(:cadence, :ground_network_credentials)
    Application.put_env(:cadence, :ground_network_credentials, %{"simulator" => @key})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :ground_network_credentials, previous),
        else: Application.delete_env(:cadence, :ground_network_credentials)
    end)

    c = ProviderChangeFixtures.setup_contact()
    realized_id = "realized-#{System.unique_integer([:positive])}"

    {:ok, _realized} =
      Cadence.Contacts.persist_realized_contact(
        c.organization_id,
        RealizedContact.new(%{
          realized_contact_id: realized_id,
          organization_id: c.organization_id,
          mission_id: c.mission_id,
          scheduled_contact_id: c.reservation.scheduled_contact_id,
          source_endpoint_refs: c.reservation.source_endpoint_refs,
          clock_mode: :live,
          initial_time: DateTime.utc_now()
        })
      )

    {:ok, gate} = SessionReadiness.start_link(policy: Policy)
    # The policy reads the booking from inside the gate process.
    Sandbox.allow(Cadence.Repo, self(), gate)

    basis = %{
      adapter_key: :tcp_socket,
      mission_id: c.mission_id,
      contact_id: realized_id,
      path_id: "uplink-path",
      binding_id: "listener",
      configuration_sha256: "config",
      peer: @peer
    }

    %{gate: gate, basis: basis, contact_ref: c.reservation.provider_contact_ref || contact_ref(c)}
  end

  test "a correctly signed provider attestation qualifies the session", ctx do
    handle = register(ctx)
    assert :ok = SessionReadiness.begin_recovery(handle, evidence(ctx, handle, "fencing"))
    assert {:ok, %{status: :recovering}} = SessionReadiness.review(handle)

    assert :ok = SessionReadiness.complete_recovery(handle, evidence(ctx, handle, "protocol"))
    assert {:ok, %{status: :ready}} = SessionReadiness.review(handle)
  end

  describe "stays unqualified" do
    test "for an attestation naming another peer", ctx do
      handle = register(ctx)

      refused!(
        handle,
        evidence(ctx, handle, "fencing", peer: "10.0.0.9:40000"),
        :attestation_peer_mismatch
      )
    end

    test "for an attestation over a stale basis", ctx do
      handle = register(ctx)
      stale = review!(handle).basis_sha256
      handle = register(ctx)

      refused!(
        handle,
        evidence(ctx, handle, "fencing", challenge: stale),
        :attestation_challenge_mismatch
      )
    end

    test "for a replayed attestation after the session re-registered", ctx do
      handle = register(ctx)
      replayed = evidence(ctx, handle, "fencing")
      handle = register(ctx)
      refused!(handle, replayed, :session_evidence_basis_changed)
    end

    test "for an attestation signed with another credential", ctx do
      handle = register(ctx)

      refused!(
        handle,
        evidence(ctx, handle, "fencing", key: "not-the-provider-credential"),
        :attestation_signature_invalid
      )
    end

    test "for an attestation about another contact or with no attestation at all", ctx do
      handle = register(ctx)

      refused!(
        handle,
        evidence(ctx, handle, "fencing", contact_ref: "someone-elses-contact"),
        :attestation_contact_mismatch
      )

      bare =
        handle |> evidence_basis() |> Map.delete(:attestation)

      refused!(handle, bare, :provider_attestation_required)
    end

    test "for protocol recovery while the FARM is locked out", ctx do
      handle = register(ctx)
      assert :ok = SessionReadiness.begin_recovery(handle, evidence(ctx, handle, "fencing"))

      assert {:error, :uplink_farm_locked_out} =
               SessionReadiness.complete_recovery(
                 handle,
                 evidence(ctx, handle, "protocol", farm: "lockout")
               )

      assert {:ok, %{status: :blocked}} = SessionReadiness.review(handle)
    end
  end

  defp register(ctx) do
    {:ok, handle} = SessionReadiness.register_provider(ctx.gate, "uplink:test", ctx.basis)
    handle
  end

  defp review!(handle) do
    {:ok, review} = SessionReadiness.review(handle)
    review
  end

  defp refused!(handle, evidence, reason) do
    assert {:error, ^reason} = SessionReadiness.begin_recovery(handle, evidence)
    assert {:ok, %{status: :blocked}} = SessionReadiness.review(handle)
    assert {:error, {:uplink_session_blocked, _}} = SessionReadiness.admit(handle)
  end

  defp evidence_basis(handle) do
    valid_until = DateTime.utc_now() |> DateTime.add(120, :second) |> DateTime.truncate(:second)

    %{
      basis_sha256: review!(handle).basis_sha256,
      reference: "provider-attestation:test",
      valid_until: valid_until
    }
  end

  defp evidence(ctx, handle, purpose, overrides \\ []) do
    base = evidence_basis(handle)

    attestation = %{
      "contact_ref" => Keyword.get(overrides, :contact_ref, ctx.contact_ref),
      "challenge" => Keyword.get(overrides, :challenge, base.basis_sha256),
      "purpose" => purpose,
      "peer" => Keyword.get(overrides, :peer, @peer),
      "farm" => Keyword.get(overrides, :farm, "unlocked"),
      "valid_until" => DateTime.to_iso8601(base.valid_until)
    }

    signature =
      :crypto.mac(
        :hmac,
        :sha256,
        Keyword.get(overrides, :key, @key),
        Policy.canonical(attestation)
      )
      |> Base.encode16(case: :lower)

    Map.put(base, :attestation, Map.put(attestation, "signature", signature))
  end

  defp contact_ref(c), do: "provider-contact-change-#{c.reservation.provider_reservation_id}"
end
