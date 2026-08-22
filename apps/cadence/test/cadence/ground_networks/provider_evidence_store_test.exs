defmodule Cadence.GroundNetworks.ProviderEvidenceStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks.ProviderEvidenceStore

  @captured_at ~U[2026-07-15 12:00:00.000000Z]

  test "canonical hashing is deterministic and exact content deduplicates per account" do
    left = %{"z" => [3, %{"b" => true, "a" => nil}], "a" => 1}
    right = %{"a" => 1, "z" => [3, %{"a" => nil, "b" => true}]}

    assert ProviderEvidenceStore.canonical_document(left) ==
             ProviderEvidenceStore.canonical_document(right)

    assert ProviderEvidenceStore.hash_document(left) == ProviderEvidenceStore.hash_document(right)

    assert {:ok, first} =
             ProviderEvidenceStore.persist("org-evidence", "account-one", evidence_attrs(left))

    assert {:ok, duplicate} =
             ProviderEvidenceStore.persist("org-evidence", "account-one", evidence_attrs(right))

    assert duplicate.provider_evidence_id == first.provider_evidence_id
    assert duplicate.content_sha256 == first.content_sha256

    assert {:ok, other_account} =
             ProviderEvidenceStore.persist("org-evidence", "account-two", evidence_attrs(right))

    refute other_account.provider_evidence_id == first.provider_evidence_id
  end

  test "recursively redacts credential material before hashing and persistence" do
    document = %{
      "authorization" => "Bearer provider-secret",
      "request" => %{
        "credential_ref" => "provider-credential://account-one",
        "headers" => [%{"api_token" => "nested-secret"}]
      }
    }

    assert {:ok, evidence} =
             ProviderEvidenceStore.persist(
               "org-redaction",
               "account-one",
               evidence_attrs(document)
             )

    assert evidence.document == %{
             "authorization" => "[REDACTED]",
             "request" => %{
               "credential_ref" => "provider-credential://account-one",
               "headers" => [%{"api_token" => "[REDACTED]"}]
             }
           }

    refute inspect(evidence) =~ "provider-secret"
    refute inspect(evidence) =~ "nested-secret"

    assert {:ok, fetched} =
             ProviderEvidenceStore.fetch("org-redaction", evidence.provider_evidence_id)

    assert fetched.document == evidence.document
    assert fetched.content_sha256 == ProviderEvidenceStore.hash_document(evidence.document)
  end

  test "bounds inline evidence and external references never carry access credentials" do
    oversized = %{"payload" => String.duplicate("x", 262_145)}

    assert {:error, :evidence_document_too_large} =
             ProviderEvidenceStore.persist(
               "org-bounds",
               "account-one",
               evidence_attrs(oversized)
             )

    external_attrs = %{
      external_object_ref: "s3://provider-evidence/account-one/event-1.json",
      schema_type: "provider-event/v1",
      media_type: "application/json",
      captured_at: @captured_at,
      byte_count: 5_000_000,
      content_sha256: String.duplicate("a", 64)
    }

    assert {:ok, external} =
             ProviderEvidenceStore.persist("org-bounds", "account-one", external_attrs)

    assert external.storage_kind == :external
    assert external.document == nil

    assert {:error, :external_object_ref_contains_query} =
             ProviderEvidenceStore.persist(
               "org-bounds",
               "account-one",
               %{external_attrs | external_object_ref: "s3://bucket/key?token=secret"}
             )

    assert {:error, :unapproved_external_object_ref} =
             ProviderEvidenceStore.persist(
               "org-bounds",
               "account-one",
               %{external_attrs | external_object_ref: "https://example.test/evidence"}
             )
  end

  test "fetch and list operations are organization and account scoped" do
    assert {:ok, evidence} =
             ProviderEvidenceStore.persist(
               "org-scope-a",
               "account-one",
               evidence_attrs(%{"id" => "event-1"})
             )

    assert {:error, :not_found} =
             ProviderEvidenceStore.fetch("org-scope-b", evidence.provider_evidence_id)

    assert [listed] =
             ProviderEvidenceStore.list("org-scope-a", provider_account_id: "account-one")

    assert listed.provider_evidence_id == evidence.provider_evidence_id
    assert ProviderEvidenceStore.list("org-scope-a", provider_account_id: "account-two") == []
    assert ProviderEvidenceStore.list("org-scope-b") == []
  end

  defp evidence_attrs(document) do
    %{
      document: document,
      schema_type: "provider-event/v1",
      media_type: "application/json",
      captured_at: @captured_at,
      metadata: %{"capture" => "poll"}
    }
  end
end
