defmodule Cadence.GroundNetworks.ProviderAuditTest do
  use Cadence.DataCase, async: false

  alias Ecto.Multi

  alias Cadence.GroundNetworks.{ProviderAudit, ProviderAuditEntry, ProviderEvidence}
  alias Cadence.OperationalEvents

  alias Cadence.Persistence.Schemas.{
    ProviderAuditEntryRow,
    ProviderEvidenceRow
  }

  @recorded_at ~U[2026-07-15 13:00:00.000000Z]

  setup do
    %{organization: organization, mission: mission} =
      persist_mission_scope("org-audit-test", "mission-audit-test")

    %{organization: organization, mission: mission}
  end

  test "organization-only entries do not invent a mission or operational projection", %{
    organization: organization
  } do
    entry =
      audit_entry(organization.organization_id,
        provider_account_id: "account-one",
        action: "provider_credential.rotated",
        outcome: "succeeded",
        credential_ref: "provider-credential://account-one/control-plane",
        credential_registry_version: 3,
        credential_backend_version: "aws-sm-version-7"
      )

    assert {:ok, persisted} = ProviderAudit.append(entry)
    assert persisted.mission_id == nil
    assert {:ok, :organization_only} = ProviderAudit.project_entry(persisted)

    assert {:ok, fetched} =
             ProviderAudit.fetch_entry(
               organization.organization_id,
               persisted.provider_audit_entry_id
             )

    assert fetched.credential_registry_version == 3

    assert [^fetched] =
             ProviderAudit.list_entries(organization.organization_id,
               provider_account_id: "account-one"
             )

    assert {:error, :not_found} =
             ProviderAudit.fetch_entry("org-audit-other", persisted.provider_audit_entry_id)
  end

  test "mission entries retain references and project idempotently with exact causality", %{
    organization: organization,
    mission: mission
  } do
    observed =
      audit_entry(organization.organization_id,
        mission_id: mission.mission_id,
        action: "provider_contact.change_observed",
        outcome: "observed",
        correlation_id: "contact-correlation-1",
        provider_account_id: "account-one",
        provider_account_grant_id: "grant-one",
        provider_id: "provider-one",
        provider_reservation_id: "reservation-one",
        provider_change_id: "change-one",
        contact_id: "contact-one",
        scheduled_contact_id: "scheduled-contact-one",
        provider_event_id: "provider-event-one",
        request_id: "request-one",
        client_reference: "client-one",
        previous_document: %{"starts_at" => "2026-07-15T14:00:00Z"},
        current_document: %{"starts_at" => "2026-07-15T14:05:00Z"},
        decision_document: %{"classification" => "material"},
        policy_document: %{"policy_version" => 4},
        evidence_references: [
          %{
            "provider_evidence_id" => "evidence-one",
            "content_sha256" => String.duplicate("b", 64)
          }
        ]
      )

    assert {:ok, persisted_observed} = ProviderAudit.append_and_project(observed)

    accepted =
      audit_entry(organization.organization_id,
        mission_id: mission.mission_id,
        action: "provider_contact.change_accepted",
        outcome: "succeeded",
        correlation_id: "contact-correlation-1",
        provider_change_id: "change-one",
        contact_id: "contact-one",
        causation_entry_id: persisted_observed.provider_audit_entry_id,
        supersedes_entry_id: persisted_observed.provider_audit_entry_id,
        actor_document: %{"kind" => "user", "id" => "user-one"}
      )

    assert {:ok, persisted_accepted} = ProviderAudit.append_and_project(accepted)
    assert {:ok, _event} = ProviderAudit.project_entry(persisted_observed)
    assert {:ok, _event} = ProviderAudit.project_entry(persisted_accepted)

    assert [accepted_event, observed_event] =
             OperationalEvents.list_events(
               organization.organization_id,
               mission.mission_id,
               source_record_kind: :provider_audit_entry,
               order: :desc
             )

    assert observed_event.causality.source_record_id ==
             persisted_observed.provider_audit_entry_id

    assert observed_event.scope["provider_account_grant_id"] == "grant-one"
    assert observed_event.previous == %{"starts_at" => "2026-07-15T14:00:00Z"}
    assert observed_event.current == %{"starts_at" => "2026-07-15T14:05:00Z"}

    assert accepted_event.causality.causation_event_id ==
             "operational_event:provider_audit_entry:#{persisted_observed.provider_audit_entry_id}"

    assert accepted_event.actor.kind == :user

    assert length(
             OperationalEvents.list_events(
               organization.organization_id,
               mission.mission_id,
               source_record_kind: :provider_audit_entry
             )
           ) == 2
  end

  test "an audit insertion failure rolls back the matching domain insert", %{
    organization: organization
  } do
    evidence = %ProviderEvidence{
      provider_evidence_id: "provider-evidence-rollback",
      organization_id: organization.organization_id,
      provider_account_id: "account-one",
      storage_kind: :inline,
      schema_type: "provider-event/v1",
      media_type: "application/json",
      captured_at: @recorded_at,
      byte_count: 2,
      content_sha256: String.duplicate("c", 64),
      document: %{},
      metadata: %{}
    }

    invalid_audit =
      audit_entry(organization.organization_id,
        action: String.duplicate("x", 201),
        outcome: "succeeded"
      )

    multi =
      Multi.new()
      |> Multi.insert(:domain_transition, ProviderEvidenceRow.changeset(evidence))
      |> ProviderAudit.put_entry(:audit_entry, invalid_audit)

    assert {:error, :audit_entry, %Ecto.Changeset{}, _changes} = Repo.transaction(multi)
    assert Repo.get(ProviderEvidenceRow, evidence.provider_evidence_id) == nil
    assert Repo.get(ProviderAuditEntryRow, invalid_audit.provider_audit_entry_id) == nil
  end

  test "audit documents are recursively redacted and bounded", %{organization: organization} do
    entry =
      audit_entry(organization.organization_id,
        action: "provider.request_completed",
        outcome: "succeeded",
        current_document: %{
          "authorization" => "Bearer raw-provider-secret",
          "result" => %{"api_token" => "nested-secret"}
        }
      )

    assert {:ok, persisted} = ProviderAudit.append(entry)
    assert persisted.current_document["authorization"] == "[REDACTED]"
    assert persisted.current_document["result"]["api_token"] == "[REDACTED]"
    refute inspect(persisted) =~ "raw-provider-secret"
    refute inspect(persisted) =~ "nested-secret"

    oversized =
      audit_entry(organization.organization_id,
        action: "provider.request_completed",
        outcome: "succeeded",
        current_document: %{"payload" => String.duplicate("x", 65_537)}
      )

    assert {:error, %Ecto.Changeset{} = changeset} = ProviderAudit.append(oversized)

    assert %{current_document: ["is too large"]} =
             Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  test "the public ledger API is append-only" do
    refute function_exported?(ProviderAudit, :update_entry, 2)
    refute function_exported?(ProviderAudit, :delete_entry, 1)
    refute function_exported?(ProviderAudit, :delete_entry, 2)
  end

  defp audit_entry(organization_id, opts) do
    ProviderAuditEntry.new(%{
      organization_id: organization_id,
      mission_id: Keyword.get(opts, :mission_id),
      provider_account_id: Keyword.get(opts, :provider_account_id),
      provider_account_grant_id: Keyword.get(opts, :provider_account_grant_id),
      provider_id: Keyword.get(opts, :provider_id),
      provider_reservation_id: Keyword.get(opts, :provider_reservation_id),
      provider_change_id: Keyword.get(opts, :provider_change_id),
      contact_id: Keyword.get(opts, :contact_id),
      scheduled_contact_id: Keyword.get(opts, :scheduled_contact_id),
      action: Keyword.get(opts, :action),
      outcome: Keyword.get(opts, :outcome),
      recorded_at: @recorded_at,
      correlation_id: Keyword.get(opts, :correlation_id),
      request_id: Keyword.get(opts, :request_id),
      client_reference: Keyword.get(opts, :client_reference),
      provider_event_id: Keyword.get(opts, :provider_event_id),
      causation_entry_id: Keyword.get(opts, :causation_entry_id),
      supersedes_entry_id: Keyword.get(opts, :supersedes_entry_id),
      credential_ref: Keyword.get(opts, :credential_ref),
      credential_registry_version: Keyword.get(opts, :credential_registry_version),
      credential_backend_version: Keyword.get(opts, :credential_backend_version),
      source_document: Keyword.get(opts, :source_document, %{"kind" => "cadence"}),
      actor_document: Keyword.get(opts, :actor_document, %{"kind" => "system"}),
      previous_document: Keyword.get(opts, :previous_document, %{}),
      current_document: Keyword.get(opts, :current_document, %{}),
      decision_document: Keyword.get(opts, :decision_document, %{}),
      policy_document: Keyword.get(opts, :policy_document, %{}),
      evidence_references: Keyword.get(opts, :evidence_references, [])
    })
  end
end
