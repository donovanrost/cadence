defmodule Cadence.Secrets.ExternalBackendTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Secrets.{ExternalBackend, Resolver}

  @descriptor %{
    provider_credential_ref: "provider-credential-external",
    organization_id: "org-one",
    provider_account_id: "account-one",
    registry_version: 2,
    backend_key: "providers/account-one/control-plane",
    metadata: %{}
  }

  test "requires HTTPS and sends a bounded, non-retrying Req request" do
    parent = self()

    req_request = fn request ->
      send(parent, {:secret_request, request})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "material" => %{"token" => "provider-secret"},
           "version" => "version-nine",
           "fingerprint" => "fingerprint-nine"
         }
       }}
    end

    assert {:error, {:invalid_external_secret_manager_url, :https_required}} =
             Resolver.resolve(@descriptor,
               secret_backend: ExternalBackend,
               secret_manager_url: "http://secrets.example.test/",
               req_request: req_request
             )

    refute_received {:secret_request, _request}

    assert {:ok, resolved} =
             Resolver.resolve(@descriptor,
               secret_backend: ExternalBackend,
               secret_manager_url: "https://secrets.example.test/",
               secret_manager_timeout_ms: 60_000,
               secret_manager_token: "manager-secret",
               req_request: req_request
             )

    assert resolved.material == %{token: "provider-secret"}
    assert resolved.backend_version == "version-nine"

    assert_receive {:secret_request, request}
    assert request[:method] == :post
    assert request[:url] == "https://secrets.example.test/v1/secrets/resolve"
    assert request[:receive_timeout] == 30_000
    assert request[:retry] == false
    assert request[:retry_log_level] == false
    assert request[:redirect_log_level] == false
    assert {"authorization", "Bearer manager-secret"} in request[:headers]
    assert request[:json].provider_credential_ref == "provider-credential-external"
    assert request[:json].operation == :resolve
  end

  test "HTTP bodies and transport details are absent from sanitized failures" do
    req_request = fn _request ->
      {:ok,
       %Req.Response{
         status: 403,
         body: %{"error" => "denied", "token" => "raw-secret"}
       }}
    end

    assert {:error, {:external_secret_manager_http_error, 403}} =
             Resolver.resolve(@descriptor,
               secret_backend: ExternalBackend,
               secret_manager_url: "https://secrets.example.test/",
               req_request: req_request
             )

    transport_failure = fn _request -> {:error, RuntimeError.exception("token=raw-secret")} end

    assert {:error, {:external_secret_manager_request_failed, :request_failed}} =
             Resolver.resolve(@descriptor,
               secret_backend: ExternalBackend,
               secret_manager_url: "https://secrets.example.test/",
               req_request: transport_failure
             )
  end
end
