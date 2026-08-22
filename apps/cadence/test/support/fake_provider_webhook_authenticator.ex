defmodule Cadence.TestSupport.FakeProviderWebhookAuthenticator do
  @moduledoc false

  @behaviour Cadence.GroundNetworks.ProviderWebhookAuthenticator

  @impl true
  def authenticate(_version, _endpoint_ref, headers, _raw_body, opts) do
    expected = Keyword.get(opts, :expected_signature, "valid-signature")

    if List.keyfind(headers, "x-provider-signature", 0) ==
         {"x-provider-signature", expected} do
      {:ok, %{"authenticated_at" => DateTime.to_iso8601(DateTime.utc_now())}}
    else
      {:error, :provider_webhook_authentication_failed}
    end
  end

  @impl true
  def normalize(raw_body, _auth_context, _opts) do
    case Jason.decode(raw_body) do
      {:ok, %{"events" => events}} when is_list(events) -> {:ok, events}
      {:ok, event} when is_map(event) -> {:ok, [event]}
      _other -> {:error, :provider_webhook_payload_invalid}
    end
  end
end
