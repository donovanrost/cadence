defmodule Cadence.Dashboards.SourceCredentialsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{
    DataSource,
    ResolvedSourceCredential,
    SourceCredentialEvent,
    SourceCredentialMaterial,
    SourceCredentialReference
  }

  alias Cadence.OperationalEvents

  @organization_id "org-source-credentials"
  @mission_id "mission-source-credentials"
  @credentials_ref "secret://org-source-credentials/dashboard/customer-rehearsal-questdb"
  @data_source_id "customer-rehearsal-questdb"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "registers and resolves a non-secret source credential reference" do
    assert {:ok, %SourceCredentialReference{} = reference, %SourceCredentialEvent{} = event} =
             SourceCredentials.register_reference(reference_attrs(),
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 16:00:00Z]
             )

    assert reference.credentials_ref == @credentials_ref
    assert reference.organization_id == @organization_id
    assert reference.mission_id == @mission_id
    assert reference.data_source_id == @data_source_id
    assert reference.owner == :customer
    assert reference.kind == :byo_tsdb_connection
    assert reference.status == :active
    assert reference.credential_version == 1
    assert reference.current_event_id == event.source_credential_event_id
    assert reference.metadata["endpoint_ref"] == "endpoint://customer/rehearsal"

    assert event.event_type == :registered
    assert event.current_status == :active
    assert event.current_credential_version == 1
    assert event.actor_id == "operator-1"
    assert event.occurred_at == ~U[2026-06-21 16:00:00.000000Z]

    assert [listed_reference] = SourceCredentials.list_references(@organization_id, @mission_id)
    assert listed_reference.credentials_ref == @credentials_ref

    assert {:ok, %ResolvedSourceCredential{} = resolved} =
             SourceCredentials.resolve(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id
             )

    assert resolved.credentials_ref == @credentials_ref
    assert resolved.credential_version == 1
    assert resolved.status == :active
    refute resolved.secret_material?
    assert resolved.metadata["endpoint_ref"] == "endpoint://customer/rehearsal"
  end

  test "resolved credential builds a redacted connection profile for a data source" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(
               reference_attrs(
                 metadata: %{
                   endpoint_ref: "endpoint://customer/rehearsal",
                   http_endpoint: "http://customer-questdb:9000"
                 }
               )
             )

    assert {:ok, resolved} =
             SourceCredentials.resolve(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id
             )

    profile =
      ResolvedSourceCredential.connection_profile(resolved, %DataSource{
        data_source_id: @data_source_id,
        organization_id: @organization_id,
        mission_id: @mission_id,
        owner: :customer,
        kind: :byo_tsdb,
        isolation_level: :customer_owned,
        metadata: %{endpoint_ref: "endpoint://customer/rehearsal"}
      })

    assert profile.credentials_ref == @credentials_ref
    assert profile.credential_provider == "questdb"
    assert profile.credential_kind == :byo_tsdb_connection
    assert profile.credential_owner == :customer
    assert profile.credential_version == 1
    assert profile.credential_status == :active
    assert profile.data_source_id == @data_source_id
    assert profile.data_source_kind == :byo_tsdb
    assert profile.data_source_owner == :customer
    assert profile.isolation_level == :customer_owned
    assert profile.endpoint_ref == "endpoint://customer/rehearsal"
    assert profile.http_endpoint == "http://customer-questdb:9000"
    refute profile.secret_material?

    unsafe_profile =
      ResolvedSourceCredential.connection_profile(
        %ResolvedSourceCredential{
          resolved
          | metadata: %{http_endpoint: "http://user:pass@questdb:9000"}
        },
        %DataSource{data_source_id: "unsafe-source", metadata: %{}}
      )

    refute Map.has_key?(unsafe_profile, :http_endpoint)
  end

  test "resolves ephemeral credential material without embedding secrets in profile evidence" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    resolver = fn %ResolvedSourceCredential{} = credential, opts ->
      assert credential.credentials_ref == @credentials_ref
      assert Keyword.fetch!(opts, :organization_id) == @organization_id

      {:ok,
       %{
         http_endpoint: "http://customer-questdb:9000",
         username: "operator",
         password: "plaintext",
         headers: [{"x-cadence-tenant", @organization_id}]
       }}
    end

    assert {:ok, %SourceCredentialMaterial{} = material} =
             SourceCredentials.resolve_material(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               credential_material_resolver: resolver
             )

    assert material.material.username == "operator"
    assert material.material.password == "plaintext"

    profile =
      SourceCredentialMaterial.redacted_connection_profile(material, %DataSource{
        data_source_id: @data_source_id,
        organization_id: @organization_id,
        mission_id: @mission_id,
        owner: :customer,
        kind: :byo_tsdb,
        isolation_level: :customer_owned,
        metadata: %{endpoint_ref: "endpoint://customer/rehearsal"}
      })

    assert profile.secret_material?
    assert profile.secret_material_fields == ["username", "password", "headers"]
    assert profile.http_endpoint == "http://customer-questdb:9000"
    refute Map.has_key?(profile, :password)
    refute Map.has_key?(profile, :bearer_token)
    refute inspect(profile) =~ "plaintext"
  end

  test "audits credential material resolution without persisting material values" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    resolver = fn %ResolvedSourceCredential{}, _opts ->
      {:ok,
       %{
         http_endpoint: "http://customer-questdb:9000",
         username: "operator",
         password: "plaintext"
       }}
    end

    assert {:ok, %SourceCredentialMaterial{}} =
             SourceCredentials.resolve_material(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               actor_id: "operator-1",
               credential_material_resolver: resolver,
               credential_material_resolution_id: "material-audit-success",
               occurred_at: ~U[2026-06-30 12:00:00Z]
             )

    assert [audit_event] =
             OperationalEvents.list_events(@organization_id, @mission_id,
               category: :security,
               subject_kind: :source_credential,
               subject_id: @credentials_ref
             )

    assert audit_event.event_id ==
             "operational_event:source_credential_material_resolution:material-audit-success"

    assert audit_event.kind == :source_credential_material_resolved
    assert audit_event.severity == :info
    assert audit_event.actor == %{kind: :user, id: "operator-1"}
    assert audit_event.subject == %{kind: :source_credential, id: @credentials_ref}
    assert audit_event.scope == %{"data_source_id" => @data_source_id}
    assert audit_event.payload["resolution_result"] == "succeeded"
    assert audit_event.payload["material_fields"] == ["http_endpoint", "password", "username"]
    assert audit_event.payload["secret_material_fields"] == ["username", "password"]
    assert audit_event.payload["resolver"] == "anonymous/2"
    refute inspect(audit_event) =~ "plaintext"
    refute inspect(audit_event) =~ "customer-questdb:9000"
  end

  test "audits credential material resolution failures with redacted reason" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    resolver = fn %ResolvedSourceCredential{}, _opts ->
      {:error, {:vault_unavailable, %{token: "secret-token"}}}
    end

    assert {:error, {:credential_material_resolution_failed, {:vault_unavailable, _details}}} =
             SourceCredentials.resolve_material(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               actor_kind: :service,
               actor_id: "dashboard-source-probe",
               credential_material_resolver: resolver,
               credential_material_resolution_id: "material-audit-failure",
               occurred_at: ~U[2026-06-30 12:01:00Z]
             )

    assert [audit_event] =
             OperationalEvents.list_events(@organization_id, @mission_id,
               category: :security,
               subject_kind: :source_credential,
               subject_id: @credentials_ref
             )

    assert audit_event.kind == :source_credential_material_resolution_failed
    assert audit_event.severity == :warning
    assert audit_event.actor == %{kind: :service, id: "dashboard-source-probe"}
    assert audit_event.payload["resolution_result"] == "failed"
    assert audit_event.payload["failure_reason"] == ["vault_unavailable", "resolver_error"]
    refute inspect(audit_event) =~ "secret-token"
  end

  test "denies credential material resolution before resolver access and audits the denial" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    test_pid = self()

    resolver = fn %ResolvedSourceCredential{}, _opts ->
      send(test_pid, :credential_material_resolver_called)
      {:ok, %{http_endpoint: "https://customer-questdb.example.test"}}
    end

    authorizer = fn %ResolvedSourceCredential{} = credential, opts ->
      assert credential.credentials_ref == @credentials_ref
      assert Keyword.fetch!(opts, :organization_id) == @organization_id
      assert Keyword.fetch!(opts, :mission_id) == @mission_id
      {:deny, {:missing_permission, %{policy: "secret-policy"}}}
    end

    assert {:error,
            {:credential_material_authorization_denied,
             {:missing_permission, %{policy: "secret-policy"}}}} =
             SourceCredentials.resolve_material(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               actor_kind: :service,
               actor_id: "dashboard-source-probe",
               credential_material_authorizer: authorizer,
               credential_material_resolver: resolver,
               credential_material_resolution_id: "material-audit-denied",
               occurred_at: ~U[2026-06-30 12:02:00Z]
             )

    refute_received :credential_material_resolver_called

    assert [audit_event] =
             OperationalEvents.list_events(@organization_id, @mission_id,
               category: :security,
               subject_kind: :source_credential,
               subject_id: @credentials_ref
             )

    assert audit_event.event_id ==
             "operational_event:source_credential_material_resolution:material-audit-denied"

    assert audit_event.kind == :source_credential_material_resolution_denied
    assert audit_event.severity == :warning
    assert audit_event.actor == %{kind: :service, id: "dashboard-source-probe"}
    assert audit_event.payload["resolution_result"] == "denied"
    assert audit_event.payload["authorization_result"] == "denied"
    assert audit_event.payload["denial_reason"] == ["missing_permission", "resolver_error"]
    assert audit_event.payload["authorizer"] == "anonymous/2"
    assert audit_event.current["resolution_result"] == "denied"
    refute inspect(audit_event) =~ "secret-policy"
    refute inspect(audit_event) =~ "customer-questdb.example.test"
  end

  test "material resolution requires an explicit resolver" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    assert {:error, :credential_material_resolver_not_configured} =
             SourceCredentials.resolve_material(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id
             )
  end

  test "configured secret backend activates the default material resolver" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    backend = fn %ResolvedSourceCredential{}, _opts ->
      {:ok, %{http_endpoint: "https://customer-questdb.example.test"}}
    end

    assert {:ok, %SourceCredentialMaterial{} = material} =
             SourceCredentials.resolve_material(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: @data_source_id,
               credential_secret_backend: backend
             )

    assert material.material.http_endpoint == "https://customer-questdb.example.test"
  end

  test "rotates a credential reference and records versioned lifecycle events" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(reference_attrs(),
               occurred_at: ~U[2026-06-21 16:00:00Z]
             )

    assert {:ok, rotated_reference, rotated_event} =
             SourceCredentials.rotate_reference(
               @credentials_ref,
               %{
                 metadata: %{external_version_ref: "vault-version-2"},
                 payload: %{external_version_ref: "vault-version-2"}
               },
               actor_id: "operator-2",
               occurred_at: ~U[2026-06-21 17:00:00Z]
             )

    assert rotated_reference.status == :active
    assert rotated_reference.credential_version == 2
    assert rotated_reference.last_rotated_at == ~U[2026-06-21 17:00:00.000000Z]
    assert rotated_reference.current_event_id == rotated_event.source_credential_event_id
    assert rotated_reference.metadata["external_version_ref"] == "vault-version-2"

    assert rotated_event.event_type == :rotated
    assert rotated_event.previous_status == :active
    assert rotated_event.current_status == :active
    assert rotated_event.previous_credential_version == 1
    assert rotated_event.current_credential_version == 2
    assert rotated_event.payload["external_version_ref"] == "vault-version-2"

    assert [latest_event, first_event] = SourceCredentials.list_events(@credentials_ref)
    assert latest_event.event_type == :rotated
    assert first_event.event_type == :registered
  end

  test "disabled credential references do not resolve until re-enabled" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    assert {:ok, disabled_reference, disabled_event} =
             SourceCredentials.disable_reference(@credentials_ref, %{},
               actor_id: "operator-3",
               occurred_at: ~U[2026-06-21 18:00:00Z]
             )

    assert disabled_reference.status == :disabled
    assert disabled_reference.disabled_at == ~U[2026-06-21 18:00:00.000000Z]
    assert disabled_event.event_type == :disabled
    assert disabled_event.previous_status == :active
    assert disabled_event.current_status == :disabled
    assert {:error, :credential_disabled} = SourceCredentials.resolve(@credentials_ref)

    assert {:ok, enabled_reference, enabled_event} =
             SourceCredentials.enable_reference(@credentials_ref, %{},
               actor_id: "operator-4",
               occurred_at: ~U[2026-06-21 19:00:00Z]
             )

    assert enabled_reference.status == :active
    assert enabled_reference.disabled_at == nil
    assert enabled_event.event_type == :enabled
    assert enabled_event.previous_status == :disabled
    assert enabled_event.current_status == :active
    assert {:ok, %ResolvedSourceCredential{}} = SourceCredentials.resolve(@credentials_ref)
  end

  test "resolver enforces requested organization mission and data source scope" do
    assert {:ok, _reference, _event} = SourceCredentials.register_reference(reference_attrs())

    assert {:error, :credential_scope_mismatch} =
             SourceCredentials.resolve(@credentials_ref, organization_id: "other-org")

    assert {:error, :credential_scope_mismatch} =
             SourceCredentials.resolve(@credentials_ref,
               organization_id: @organization_id,
               mission_id: "other-mission"
             )

    assert {:error, :credential_scope_mismatch} =
             SourceCredentials.resolve(@credentials_ref,
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "other-source"
             )
  end

  test "rejects secret-shaped metadata and event payloads" do
    assert {:error, %Ecto.Changeset{} = changeset} =
             SourceCredentials.register_reference(
               reference_attrs(metadata: %{connection: %{password: "plaintext"}})
             )

    assert "must not embed credentials or secrets" in field_errors(changeset, :metadata)

    assert {:ok, reference, _event} = SourceCredentials.register_reference(reference_attrs())

    assert {:error, %Ecto.Changeset{} = rotation_changeset} =
             SourceCredentials.rotate_reference(@credentials_ref, %{
               payload: %{token: "plaintext"}
             })

    assert "must not embed credentials or secrets" in field_errors(rotation_changeset, :payload)

    assert {:ok, fetched_reference} = SourceCredentials.fetch_reference(@credentials_ref)
    assert fetched_reference.credential_version == reference.credential_version
  end

  defp reference_attrs(overrides \\ []) do
    attrs = %{
      credentials_ref: @credentials_ref,
      organization_id: @organization_id,
      mission_id: @mission_id,
      data_source_id: @data_source_id,
      owner: :customer,
      kind: :byo_tsdb_connection,
      provider: "questdb",
      metadata: %{endpoint_ref: "endpoint://customer/rehearsal"}
    }

    Map.merge(attrs, Map.new(overrides))
  end

  defp field_errors(%Ecto.Changeset{} = changeset, field) do
    for {^field, {message, _opts}} <- changeset.errors, do: message
  end
end
