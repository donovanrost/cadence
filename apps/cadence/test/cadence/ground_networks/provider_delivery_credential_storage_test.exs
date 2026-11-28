defmodule Cadence.GroundNetworks.ProviderDeliveryCredentialStorageTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks.ProviderDeliveryCredentials.{CredentialRow, GenerationRow}

  test "credential and generation history survives attempted updates, deletions and truncation" do
    credential =
      Repo.insert!(%CredentialRow{
        credential_ref: "delivery_credential_storage_test",
        organization_id: "organization-storage-test",
        mission_id: "mission-storage-test",
        provider_id: "provider-storage-test",
        provider_account_id: "account-storage-test",
        provider_account_grant_id: "grant-storage-test",
        provider_binding_id: "transport-storage-test"
      })

    ref = credential.credential_ref

    assert_guard_refuses(
      "DELETE FROM provider_delivery_credentials WHERE credential_ref = $1",
      [ref]
    )

    leaf =
      Repo.insert!(%GenerationRow{
        fingerprint: "leaf-storage-test",
        public_key_fingerprint: "key-storage-test",
        credential_ref: ref,
        generation: 1,
        state: :current,
        expires_at: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)
      })

    assert_guard_refuses(
      "DELETE FROM provider_delivery_certificate_generations WHERE fingerprint = $1",
      [leaf.fingerprint]
    )

    now = DateTime.utc_now()
    Repo.update!(change(leaf, state: :revoked, revoked_at: now))
    Repo.update!(change(credential, retired_at: now))

    assert_guard_refuses(
      "UPDATE provider_delivery_certificate_generations SET state = 'current', revoked_at = NULL WHERE fingerprint = $1",
      [leaf.fingerprint]
    )

    assert_guard_refuses(
      "UPDATE provider_delivery_credentials SET retired_at = NULL WHERE credential_ref = $1",
      [ref]
    )

    assert_guard_refuses("TRUNCATE provider_delivery_credentials CASCADE", [])
    assert_guard_refuses("TRUNCATE provider_delivery_certificate_generations", [])
    assert Repo.get!(GenerationRow, leaf.fingerprint).state == :revoked
    assert Repo.get!(CredentialRow, ref).retired_at == now
  end

  defp assert_guard_refuses(sql, params) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation, message: message}}} =
             Repo.query(sql, params, mode: :savepoint)

    assert message =~ "cannot be removed or changed after revocation or retirement"
  end
end
