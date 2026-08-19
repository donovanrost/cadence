defmodule Cadence.GroundNetworks.ProviderCredentialsTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.GroundNetworks.{CredentialResolver, ProviderAudit, ProviderCredentials}

  @organization_id "org-provider-credentials"
  @account_id "provider-account-one"
  @credential_ref "provider-credential-control-plane"
  @now ~U[2026-07-15 15:00:00.000000Z]

  test "creates, resolves, rotates, and revokes one stable external credential reference" do
    parent = self()

    req_request = fn request ->
      operation = request[:json].operation
      send(parent, {:backend_operation, operation, request})

      body =
        case operation do
          :create ->
            %{
              "backend_reference" => "secret-manager://providers/account-one",
              "version" => "backend-v1",
              "fingerprint" => "fingerprint-v1"
            }

          :resolve ->
            %{
              "material" => %{"value" => "provider-control-plane-secret"},
              "version" => "backend-v1",
              "fingerprint" => "fingerprint-v1",
              "expires_at" => "2026-07-16T15:00:00Z"
            }

          :rotate ->
            %{"version" => "backend-v2", "fingerprint" => "fingerprint-v2"}

          :revoke ->
            %{"version" => "backend-v3", "fingerprint" => "fingerprint-v3"}
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end

    opts = backend_opts(req_request)

    assert {:ok, created} =
             ProviderCredentials.create(
               @organization_id,
               @account_id,
               credential_attrs(),
               opts
             )

    assert created.provider_credential_ref == @credential_ref
    assert created.registry_version == 1
    assert created.backend_reference == "secret-manager://providers/account-one"
    refute inspect(created) =~ "provider-control-plane-secret"

    assert_receive {:backend_operation, :create, create_request}
    refute inspect(create_request[:json]) =~ "provider-control-plane-secret"

    assert {:ok, resolved} =
             ProviderCredentials.resolve(
               @organization_id,
               @account_id,
               @credential_ref,
               opts
             )

    assert resolved.material == %{value: "provider-control-plane-secret"}
    assert resolved.registry_version == 1
    assert resolved.backend_version == "backend-v1"
    assert resolved.fingerprint == "fingerprint-v1"
    refute inspect(resolved) =~ "provider-control-plane-secret"

    assert {:ok, "provider-control-plane-secret"} =
             CredentialResolver.resolve(@credential_ref, opts)

    assert {:ok, rotated} =
             ProviderCredentials.rotate(
               @organization_id,
               @account_id,
               @credential_ref,
               opts
             )

    assert rotated.provider_credential_ref == @credential_ref
    assert rotated.registry_version == 2
    assert rotated.last_rotated_at == @now

    assert {:ok, revoked} =
             ProviderCredentials.revoke(
               @organization_id,
               @account_id,
               @credential_ref,
               opts
             )

    assert revoked.provider_credential_ref == @credential_ref
    assert revoked.registry_version == 3
    assert revoked.status == :revoked
    assert revoked.revoked_at == @now

    assert {:error, :provider_credential_revoked} =
             ProviderCredentials.resolve(
               @organization_id,
               @account_id,
               @credential_ref,
               opts
             )

    actions =
      @organization_id
      |> ProviderAudit.list_entries(provider_account_id: @account_id, limit: 20)
      |> Enum.map(& &1.action)

    assert "provider_credential.created" in actions
    assert "provider_credential.resolved" in actions
    assert "provider_credential.rotated" in actions
    assert "provider_credential.revoked" in actions
    assert "provider_credential.resolution_failed" in actions

    audit_text = inspect(ProviderAudit.list_entries(@organization_id, limit: 20))
    refute audit_text =~ "provider-control-plane-secret"
    assert audit_text =~ "backend-v2"
    assert audit_text =~ "fingerprint-v2"
  end

  test "enforces Provider Account scope and local-only environment policy" do
    assert {:ok, credential} =
             ProviderCredentials.create(
               @organization_id,
               @account_id,
               credential_attrs(
                 provider_credential_ref: "provider-credential-env",
                 backend_type: :env,
                 backend_key: "CADENCE_PROVIDER_ACCOUNT_TOKEN"
               ),
               manage_backend?: false,
               now: @now
             )

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.fetch(
               @organization_id,
               "another-account",
               credential.provider_credential_ref
             )

    audit_count = length(ProviderAudit.list_entries(@organization_id, limit: 20))

    assert {:error, :provider_credential_not_found} =
             ProviderCredentials.rotate(
               @organization_id,
               "another-account",
               credential.provider_credential_ref,
               manage_backend?: false,
               now: @now
             )

    assert length(ProviderAudit.list_entries(@organization_id, limit: 20)) == audit_count

    assert {:error, :env_secret_backend_local_only} =
             ProviderCredentials.resolve(
               @organization_id,
               @account_id,
               credential.provider_credential_ref,
               allow_local_provider_credentials?: false,
               now: @now
             )

    assert {:ok, resolved} =
             ProviderCredentials.resolve(
               @organization_id,
               @account_id,
               credential.provider_credential_ref,
               allow_local_provider_credentials?: true,
               env_reader: fn "CADENCE_PROVIDER_ACCOUNT_TOKEN" -> "local-provider-secret" end,
               now: @now
             )

    assert resolved.material == %{value: "local-provider-secret"}
    refute inspect(resolved) =~ "local-provider-secret"

    assert {:error, {:secret_backend_capability_not_supported, :rotate}} =
             ProviderCredentials.rotate(
               @organization_id,
               @account_id,
               credential.provider_credential_ref,
               manage_backend?: true,
               now: @now
             )
  end

  test "never persists material-like metadata" do
    assert {:error, %Ecto.Changeset{} = changeset} =
             ProviderCredentials.create(
               @organization_id,
               @account_id,
               credential_attrs(metadata: %{"api_token" => "must-not-persist"}),
               manage_backend?: false,
               now: @now
             )

    assert %{metadata: ["must not embed credentials or secrets"]} =
             Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    assert ProviderCredentials.list(@organization_id, @account_id) == []
    refute inspect(ProviderAudit.list_entries(@organization_id)) =~ "must-not-persist"
  end

  defp credential_attrs(overrides \\ []) do
    %{
      provider_credential_ref: Keyword.get(overrides, :provider_credential_ref, @credential_ref),
      backend_type: Keyword.get(overrides, :backend_type, :external),
      backend_key: Keyword.get(overrides, :backend_key, "providers/account-one/control-plane"),
      registered_at: @now,
      metadata: Keyword.get(overrides, :metadata, %{"purpose" => "control-plane"})
    }
  end

  defp backend_opts(req_request) do
    [
      secret_manager_url: "https://secrets.example.test/",
      secret_manager_token: "secret-manager-auth-token",
      req_request: req_request,
      now: @now
    ]
  end
end
