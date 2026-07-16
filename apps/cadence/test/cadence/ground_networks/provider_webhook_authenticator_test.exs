defmodule Cadence.GroundNetworks.ProviderWebhookAuthenticatorTest do
  use Cadence.DataCase, async: false

  alias Cadence.GroundNetworks.{
    ProviderAccounts,
    ProviderCredentials,
    ProviderEventInbox,
    ProviderWebhookAuthenticator
  }

  alias Cadence.TestSupport.FakeProviderWebhookAuthenticator

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-webhook-#{suffix}"
    persist_mission_scope(organization_id, "mission-provider-webhook-#{suffix}")
    version = persist_account!(organization_id, suffix)

    %{organization_id: organization_id, version: version}
  end

  test "a provider type without an explicit authenticator cannot enable a route", context do
    assert {:error, :provider_webhook_authenticator_not_configured} =
             ProviderWebhookAuthenticator.ensure_enabled(context.version)
  end

  test "authenticated bounded deliveries reuse the durable inbox", context do
    opts = [authenticator_registry: &authenticator_registry/1]
    headers = [{"x-provider-signature", "valid-signature"}]
    body = Jason.encode!(%{"events" => [event_document()]})

    assert {:ok, %{inserted: 1, quarantined: 0, entries: [entry]}} =
             ProviderWebhookAuthenticator.authenticate_and_ingest(
               context.version,
               "primary-webhook",
               headers,
               body,
               opts
             )

    assert entry.channel_ref == "primary-webhook"
    assert entry.provider_event_cursor_id == nil
    assert entry.processing_state == :received
    assert [_entry] = ProviderEventInbox.list(context.organization_id)
  end

  test "authentication and body bounds fail before inbox persistence", context do
    opts = [authenticator_registry: &authenticator_registry/1]
    body = Jason.encode!(event_document())

    assert {:error, :provider_webhook_authentication_failed} =
             ProviderWebhookAuthenticator.authenticate_and_ingest(
               context.version,
               "primary-webhook",
               [],
               body,
               opts
             )

    assert {:error, :provider_webhook_body_too_large} =
             ProviderWebhookAuthenticator.authenticate_and_ingest(
               context.version,
               "primary-webhook",
               [{"x-provider-signature", "valid-signature"}],
               body,
               Keyword.put(opts, :body_byte_limit, 10)
             )

    assert ProviderEventInbox.list(context.organization_id) == []
  end

  defp authenticator_registry(:simulator), do: {:ok, FakeProviderWebhookAuthenticator}

  defp event_document do
    %{
      "id" => "event-webhook-one",
      "schema_version" => "1.0",
      "sequence" => 1,
      "occurred_at" => "2026-07-15T11:59:00.000000Z",
      "type" => "contact.status_changed",
      "resource_type" => "contact",
      "resource_id" => "provider-contact-one",
      "resource_revision" => 1,
      "client_reference" => "cadence-contact-one",
      "data" => %{"status" => "confirmed"}
    }
  end

  defp persist_account!(organization_id, suffix) do
    account_id = "provider-account-webhook-#{suffix}"
    credential_ref = "provider-credential-webhook-#{suffix}"

    assert {:ok, _credential} =
             ProviderCredentials.create(
               organization_id,
               account_id,
               %{
                 provider_credential_ref: credential_ref,
                 backend_type: :external,
                 backend_key: "providers/#{suffix}/webhook"
               },
               manage_backend?: false
             )

    assert {:ok, _account, version} =
             ProviderAccounts.create_for_system(
               organization_id,
               %{
                 provider_account_id: account_id,
                 display_name: "Webhook Account",
                 provider_type: :simulator,
                 base_url: "http://simulator.test",
                 environment_ref: "environment-#{suffix}",
                 credential_ref: credential_ref,
                 event_ingestion_mode: :hybrid
               },
               %{"kind" => "system", "id" => "webhook-test"},
               validate_credential?: false
             )

    version
  end
end
