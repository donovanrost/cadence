defmodule Cadence.GroundNetworks.ProviderEventCursorsTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks.{
    ProviderAccounts,
    ProviderCredentials,
    ProviderEventCursors
  }

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-cursor-#{suffix}"
    persist_mission_scope(organization_id, "mission-provider-cursor-#{suffix}")
    account_version = persist_account!(organization_id, suffix)

    %{organization_id: organization_id, account_version: account_version}
  end

  test "one durable cursor exists for an exact account stream", context do
    assert {:ok, first} = ProviderEventCursors.ensure(context.account_version)
    assert {:ok, second} = ProviderEventCursors.ensure(context.account_version)

    assert first.provider_event_cursor_id == second.provider_event_cursor_id
    assert first.provider_account_version == context.account_version.version
    assert first.environment_ref == context.account_version.environment_ref
    assert first.channel_ref == "default"
    assert first.stream_ref == "events"

    assert [listed] =
             ProviderEventCursors.list(context.organization_id,
               provider_account_id: context.account_version.provider_account_id
             )

    assert listed.provider_event_cursor_id == first.provider_event_cursor_id
  end

  test "leases exclude concurrent pollers and can be reclaimed after expiry", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    assert {:ok, cursor} = ProviderEventCursors.ensure(context.account_version)

    assert {:ok, claimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "poller-one",
               now: now,
               lease_ms: 1_000
             )

    assert claimed.lease_owner == "poller-one"

    assert {:error, :lease_unavailable} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "poller-two",
               now: now,
               lease_ms: 1_000
             )

    assert {:ok, reclaimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "poller-two",
               now: DateTime.add(now, 1_001, :millisecond),
               lease_ms: 1_000
             )

    assert reclaimed.lease_owner == "poller-two"
  end

  test "a failed fetch releases the lease and records bounded health evidence", context do
    now = ~U[2026-07-15 12:00:00.000000Z]
    assert {:ok, cursor} = ProviderEventCursors.ensure(context.account_version)

    assert {:ok, claimed} =
             ProviderEventCursors.claim(cursor.provider_event_cursor_id, "poller", now: now)

    assert {:ok, failed} =
             ProviderEventCursors.record_failure(
               claimed,
               "poller",
               {:provider_unavailable, :timeout},
               now: now
             )

    assert failed.health == :degraded
    assert failed.lease_owner == nil
    assert failed.consecutive_failures == 1
    assert failed.error_document["reason"] == %{"tuple" => ["provider_unavailable", "timeout"]}
  end

  defp persist_account!(organization_id, suffix) do
    account_id = "provider-account-cursor-#{suffix}"
    credential_ref = "provider-credential-cursor-#{suffix}"

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
                 display_name: "Cursor Account",
                 provider_type: :simulator,
                 base_url: "http://simulator.test",
                 environment_ref: "environment-#{suffix}",
                 credential_ref: credential_ref,
                 event_configuration: %{
                   "channel_ref" => "default",
                   "stream_ref" => "events"
                 }
               },
               %{"kind" => "system", "id" => "cursor-test"},
               validate_credential?: false
             )

    version
  end
end
