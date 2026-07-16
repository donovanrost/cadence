defmodule Cadence.GroundNetworks.ProviderEventPollerTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks.{
    ProviderAccounts,
    ProviderCredentials,
    ProviderEventCursors,
    ProviderEventInbox,
    ProviderEventPoller
  }

  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-poller-#{suffix}"
    persist_mission_scope(organization_id, "mission-provider-poller-#{suffix}")
    {account, version, credential} = persist_account!(organization_id, suffix)

    %{
      organization_id: organization_id,
      account: account,
      version: version,
      credential: credential,
      suffix: suffix
    }
  end

  test "first and duplicate pages advance durable cursor state", context do
    now = ~U[2026-07-15 12:00:00.000000Z]

    page = %{
      data: [event_document("event-poller", 1)],
      next_cursor: "cursor-one",
      truncated: false
    }

    assert {:ok, %{accounts: 1, polled: 1, events: 1, errors: 0}} =
             ProviderEventPoller.poll_once(poll_opts(context, now, {:ok, page}))

    assert [cursor] =
             ProviderEventCursors.list(context.organization_id,
               provider_account_id: context.account.provider_account_id
             )

    assert cursor.cursor == "cursor-one"
    assert [_entry] = ProviderEventInbox.list(context.organization_id)

    second_page = %{page | next_cursor: "cursor-two"}

    assert {:ok, %{accounts: 1, polled: 1, events: 1, errors: 0}} =
             ProviderEventPoller.poll_once(
               poll_opts(context, DateTime.add(now, 1, :second), {:ok, second_page})
             )

    assert [cursor] = ProviderEventCursors.list(context.organization_id)
    assert cursor.cursor == "cursor-two"
    assert [_entry] = ProviderEventInbox.list(context.organization_id)
  end

  test "revoked credentials fail before the provider call and degrade cursor health", context do
    assert {:ok, _revoked} =
             ProviderCredentials.revoke(
               context.organization_id,
               context.account.provider_account_id,
               context.credential.provider_credential_ref,
               manage_backend?: false
             )

    test_pid = self()

    assert {:ok, %{accounts: 1, polled: 0, errors: 1}} =
             ProviderEventPoller.poll_once(
               poll_opts(context, ~U[2026-07-15 12:00:00.000000Z], {:ok, empty_page()},
                 on_events: fn _cursor -> send(test_pid, :provider_called) end
               )
             )

    refute_received :provider_called
    assert [cursor] = ProviderEventCursors.list(context.organization_id)
    assert cursor.health == :degraded
    assert cursor.error_document["reason"] == "provider_credential_revoked"
  end

  test "account batches enforce configured concurrency", context do
    accounts =
      [{context.account, context.version}] ++
        Enum.map(1..3, fn offset ->
          {account, version, _credential} =
            persist_account!(context.organization_id, context.suffix + offset)

          {account, version}
        end)

    {:ok, tracker} = Agent.start_link(fn -> %{active: 0, maximum: 0} end)

    on_events = fn _cursor ->
      Agent.update(tracker, fn state ->
        active = state.active + 1
        %{active: active, maximum: max(state.maximum, active)}
      end)

      Process.sleep(40)
      Agent.update(tracker, &%{&1 | active: &1.active - 1})
    end

    opts =
      context
      |> poll_opts(~U[2026-07-15 12:00:00.000000Z], {:ok, empty_page()}, on_events: on_events)
      |> Keyword.put(:accounts, accounts)
      |> Keyword.put(:max_concurrency, 2)

    assert {:ok, %{accounts: 4, polled: 4, errors: 0}} = ProviderEventPoller.poll_once(opts)
    assert Agent.get(tracker, & &1.maximum) == 2
  end

  test "polling discovery uses only active polling and hybrid account versions", context do
    {_disabled_account, disabled_version, _credential} =
      persist_account!(context.organization_id, context.suffix + 10,
        event_ingestion_mode: :disabled
      )

    polling_ids =
      ProviderAccounts.list_polling_accounts()
      |> Enum.filter(fn {_account, version} ->
        version.organization_id == context.organization_id
      end)
      |> Enum.map(fn {_account, version} -> version.provider_account_id end)

    assert context.account.provider_account_id in polling_ids
    refute disabled_version.provider_account_id in polling_ids
  end

  defp poll_opts(context, now, events_response, extra \\ []) do
    [
      accounts: [{context.account, context.version}],
      client: FakeProviderClient,
      events_response: events_response,
      lease_owner: "poller-test",
      now: now,
      secret_backend: &secret_backend/2
    ] ++ extra
  end

  defp secret_backend(_descriptor, _opts) do
    {:ok,
     %{
       material: %{bearer_token: "ephemeral-provider-token"},
       backend_version: "version-one"
     }}
  end

  defp empty_page, do: %{data: [], next_cursor: nil, truncated: false}

  defp event_document(id, sequence) do
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
      "data" => %{"status" => "confirmed"}
    }
  end

  defp persist_account!(organization_id, suffix, opts \\ []) do
    account_id = "provider-account-poller-#{suffix}"
    credential_ref = "provider-credential-poller-#{suffix}"

    assert {:ok, credential} =
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

    assert {:ok, account, version} =
             ProviderAccounts.create_for_system(
               organization_id,
               %{
                 provider_account_id: account_id,
                 display_name: "Poller Account #{suffix}",
                 provider_type: :simulator,
                 base_url: "http://simulator.test",
                 environment_ref: "environment-#{suffix}",
                 credential_ref: credential_ref,
                 event_ingestion_mode: Keyword.get(opts, :event_ingestion_mode, :polling)
               },
               %{"kind" => "system", "id" => "poller-test"},
               validate_credential?: false
             )

    {account, version, credential}
  end
end
