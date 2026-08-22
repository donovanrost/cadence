defmodule Cadence.GroundNetworks.ProviderEventInboxTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks.{
    ProviderAccounts,
    ProviderAudit,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox
  }

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-inbox-#{suffix}"
    persist_mission_scope(organization_id, "mission-provider-inbox-#{suffix}")
    account_version = persist_account!(organization_id, suffix)
    {:ok, cursor} = ProviderEventCursors.ensure(account_version)

    %{
      organization_id: organization_id,
      account_version: account_version,
      cursor: cursor,
      suffix: suffix
    }
  end

  test "page ingestion stores events and advances the cursor in one commit", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    cursor = claim!(context.cursor, "poller-one", now)
    event = event_document("event-one", 1, %{"api_token" => "secret"})

    assert {:ok, %{inserted: 1, duplicates: 0, quarantined: 0, entries: [entry]}} =
             ProviderEventInbox.ingest_page(cursor, [event], "cursor-one", "poller-one", now: now)

    assert entry.processing_state == :received
    assert entry.payload_document["data"]["api_token"] == "[REDACTED]"
    assert String.length(entry.content_sha256) == 64

    assert {:ok, advanced} =
             ProviderEventCursors.fetch(context.organization_id, cursor.provider_event_cursor_id)

    assert advanced.cursor == "cursor-one"
    assert advanced.health == :healthy
    assert advanced.lease_owner == nil
    assert advanced.last_event_at == ~U[2026-07-15 11:59:00.000000Z]

    actions =
      context.organization_id
      |> ProviderAudit.list_entries(
        provider_account_id: context.account_version.provider_account_id
      )
      |> Enum.map(& &1.action)

    assert "provider_event.page_ingested" in actions
  end

  test "duplicate content is idempotent while identity collisions are immutable quarantine rows",
       context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    original = event_document("event-shared", 1, %{"status" => "pending"})

    cursor = claim!(context.cursor, "poller-one", now)

    assert {:ok, %{inserted: 1}} =
             ProviderEventInbox.ingest_page(cursor, [original], "cursor-one", "poller-one",
               now: now
             )

    {:ok, cursor} =
      ProviderEventCursors.fetch(context.organization_id, cursor.provider_event_cursor_id)

    cursor = claim!(cursor, "poller-two", DateTime.add(now, 1, :second))

    assert {:ok, %{duplicates: 1, inserted: 0}} =
             ProviderEventInbox.ingest_page(
               cursor,
               [original],
               "cursor-two",
               "poller-two",
               now: DateTime.add(now, 1, :second)
             )

    {:ok, cursor} =
      ProviderEventCursors.fetch(context.organization_id, cursor.provider_event_cursor_id)

    cursor = claim!(cursor, "poller-three", DateTime.add(now, 2, :second))
    collision = put_in(original, ["data", "status"], "confirmed")

    assert {:ok, %{collisions: 1, quarantined: 1, entries: [collision_entry]}} =
             ProviderEventInbox.ingest_page(
               cursor,
               [collision],
               "cursor-three",
               "poller-three",
               now: DateTime.add(now, 2, :second)
             )

    assert collision_entry.identity_collision
    assert collision_entry.processing_state == :quarantined
    assert collision_entry.error_document["category"] == "provider_event_identity_collision"

    assert [first, second] =
             context.organization_id
             |> ProviderEventInbox.list(
               provider_account_id: context.account_version.provider_account_id
             )
             |> Enum.sort_by(& &1.received_at)

    assert first.provider_event_id == second.provider_event_id
    refute first.content_sha256 == second.content_sha256
    refute first.payload_document == second.payload_document
  end

  test "unknown and malformed events quarantine without blocking later cursor progress",
       context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    cursor = claim!(context.cursor, "poller", now)

    unknown = %{event_document("event-unknown", 4) | "type" => "vendor.future_event"}
    malformed = %{event_document("event-poison", 5) | "occurred_at" => "not-a-time"}
    valid = event_document("event-valid", 6)

    assert {:ok, %{inserted: 3, quarantined: 2, entries: entries}} =
             ProviderEventInbox.ingest_page(
               cursor,
               [unknown, malformed, valid],
               "cursor-after-poison",
               "poller",
               now: now
             )

    states = Map.new(entries, &{&1.provider_event_id, &1.processing_state})
    assert states["event-unknown"] == :quarantined
    assert states["event-poison"] == :quarantined
    assert states["event-valid"] == :received

    assert {:ok, advanced} =
             ProviderEventCursors.fetch(context.organization_id, cursor.provider_event_cursor_id)

    assert advanced.cursor == "cursor-after-poison"
  end

  test "a restart before cursor commit replays the page without a lost inbox row", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    cursor = claim!(context.cursor, "poller", now)
    event = event_document("event-restart", 1)

    assert {:error, {:injected_failure, :injected_before_cursor_commit}} =
             ProviderEventInbox.ingest_page(cursor, [event], "cursor-one", "poller",
               now: now,
               fail_before_cursor_commit?: true
             )

    assert ProviderEventInbox.list(context.organization_id) == []

    assert {:ok, unchanged} =
             ProviderEventCursors.fetch(context.organization_id, cursor.provider_event_cursor_id)

    assert unchanged.cursor == nil
    assert unchanged.lease_owner == "poller"

    assert {:ok, %{inserted: 1}} =
             ProviderEventInbox.ingest_page(unchanged, [event], "cursor-one", "poller", now: now)

    assert [_entry] = ProviderEventInbox.list(context.organization_id)
  end

  test "out-of-order sequences remain evidence and both enter processing", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    cursor = claim!(context.cursor, "poller", now)

    assert {:ok, %{inserted: 2, entries: entries}} =
             ProviderEventInbox.ingest_page(
               cursor,
               [event_document("event-two", 2), event_document("event-one", 1)],
               "cursor-two",
               "poller",
               now: now
             )

    assert Enum.map(entries, & &1.sequence) == [2, 1]
    assert Enum.all?(entries, &(&1.processing_state == :received))
  end

  defp claim!(cursor, owner, now) do
    assert {:ok, claimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, owner, now: now)

    claimed
  end

  defp event_document(id, sequence, data \\ %{}) do
    %{
      "id" => id,
      "schema_version" => "1.0",
      "sequence" => sequence,
      "occurred_at" => "2026-07-15T11:59:00.000000Z",
      "type" => "contact.status_changed",
      "resource_type" => "contact",
      "resource_id" => "provider-contact-one",
      "resource_revision" => 1,
      "client_reference" => "cadence-contact-one",
      "data" => data
    }
  end

  defp persist_account!(organization_id, suffix) do
    account_id = "provider-account-inbox-#{suffix}"
    credential_ref = "provider-credential-inbox-#{suffix}"

    assert {:ok, _credential} =
             ProviderCredentials.create(
               organization_id,
               account_id,
               %{
                 provider_credential_ref: credential_ref,
                 backend_type: :external,
                 backend_key: "providers/#{suffix}/control-plane"
               },
               manage_backend?: false
             )

    assert {:ok, _account, version} =
             ProviderAccounts.create_for_system(
               organization_id,
               %{
                 provider_account_id: account_id,
                 display_name: "Inbox Account",
                 provider_type: :simulator,
                 base_url: "http://simulator.test",
                 environment_ref: "environment-#{suffix}",
                 credential_ref: credential_ref
               },
               %{"kind" => "system", "id" => "inbox-test"},
               validate_credential?: false
             )

    version
  end
end
