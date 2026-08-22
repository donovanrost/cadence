defmodule Cadence.Dashboards.SourceCredentialSecretCompatibilityTest do
  use Cadence.UnitCase, async: true

  alias Cadence.DataSources.ResolvedSourceCredential

  alias Cadence.Management.DataSources.Credentials.{
    EnvMaterialResolver,
    ExternalSecretBackend,
    SecretMaterialResolver
  }

  alias Cadence.Secrets.MaterialPolicy

  @organization_id "org-source-credentials"
  @mission_id "mission-source-credentials"
  @credentials_ref "secret://org-source-credentials/dashboard/customer-rehearsal-questdb"
  @data_source_id "customer-rehearsal-questdb"

  @credential %ResolvedSourceCredential{
    credentials_ref: @credentials_ref,
    organization_id: @organization_id,
    mission_id: @mission_id,
    data_source_id: @data_source_id,
    owner: :customer,
    kind: :byo_tsdb_connection,
    provider: "questdb",
    status: :active,
    credential_version: 1,
    current_event_id: "source-credential-event-1",
    metadata: %{"endpoint_ref" => "endpoint://customer/rehearsal"}
  }

  test "secret material resolver translates dashboard backend options and allow-list" do
    parent = self()

    backend = fn credential, opts ->
      send(parent, {:secret_backend_called, credential, opts})

      {:ok,
       %{
         "http_endpoint" => "https://customer-questdb.example.test",
         "username" => "quest-user",
         "password" => "quest-password",
         "headers" => %{"x-cadence-tenant" => @organization_id},
         "unused_material" => "ignored"
       }}
    end

    assert {:ok, material} =
             SecretMaterialResolver.resolve(@credential,
               credential_secret_backend: backend,
               organization_id: @organization_id,
               dashboard_option: :preserved
             )

    assert material == %{
             http_endpoint: "https://customer-questdb.example.test",
             username: "quest-user",
             password: "quest-password",
             headers: [{"x-cadence-tenant", @organization_id}]
           }

    assert_receive {:secret_backend_called, %ResolvedSourceCredential{} = credential,
                    resolver_opts}

    assert credential == @credential
    assert Keyword.fetch!(resolver_opts, :credential_secret_backend) == backend
    assert Keyword.fetch!(resolver_opts, :secret_backend) == backend

    assert Keyword.fetch!(resolver_opts, :allowed_material_keys) ==
             MaterialPolicy.dashboard_keys()

    refute Keyword.fetch!(resolver_opts, :sanitize_secret_errors?)
    assert Keyword.fetch!(resolver_opts, :dashboard_option) == :preserved
  end

  test "external backend keeps the dashboard secret-manager path" do
    parent = self()

    req_request = fn request ->
      send(parent, {:external_secret_request, request})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "material" => %{
             "http_endpoint" => "https://customer-questdb.example.test",
             "bearer_token" => "secret-bearer"
           }
         }
       }}
    end

    assert {:ok, material} =
             ExternalSecretBackend.fetch_material(@credential,
               secret_manager_url: "https://secrets.example.test/",
               secret_manager_token_env: "CADENCE_TEST_SECRET_MANAGER_TOKEN",
               env_reader: fn
                 "CADENCE_TEST_SECRET_MANAGER_TOKEN" -> "secret-manager-token"
                 _env_var -> nil
               end,
               req_request: req_request
             )

    assert material == %{
             "http_endpoint" => "https://customer-questdb.example.test",
             "bearer_token" => "secret-bearer"
           }

    assert_receive {:external_secret_request, request}
    assert request[:method] == :post

    assert request[:url] ==
             "https://secrets.example.test/v1/dashboard-source-credentials/material"

    assert {"authorization", "Bearer secret-manager-token"} in request[:headers]
    assert request[:json].operation == :resolve
    assert request[:json].credentials_ref == @credentials_ref
    assert request[:json].organization_id == @organization_id
    assert request[:json].mission_id == @mission_id
    assert request[:json].data_source_id == @data_source_id
    assert request[:json].credential_version == 1
    assert request[:json].metadata == %{"endpoint_ref" => "endpoint://customer/rehearsal"}
  end

  test "environment resolver accepts dashboard profile options without global state" do
    profiles = %{
      @credentials_ref => %{
        "http_endpoint_env" => "CADENCE_TEST_BYO_HTTP_ENDPOINT",
        "username_env" => "CADENCE_TEST_BYO_USERNAME",
        "password_env" => "CADENCE_TEST_BYO_PASSWORD",
        "headers_env" => %{"x-cadence-tenant" => "CADENCE_TEST_BYO_TENANT"}
      }
    }

    env_reader = fn
      "CADENCE_TEST_BYO_HTTP_ENDPOINT" -> "https://customer-questdb.example.test"
      "CADENCE_TEST_BYO_USERNAME" -> "quest-user"
      "CADENCE_TEST_BYO_PASSWORD" -> "quest-password"
      "CADENCE_TEST_BYO_TENANT" -> @organization_id
      _env_var -> nil
    end

    assert {:ok, material} =
             EnvMaterialResolver.resolve(@credential,
               env_material_profiles: profiles,
               env_reader: env_reader
             )

    assert material == %{
             http_endpoint: "https://customer-questdb.example.test",
             username: "quest-user",
             password: "quest-password",
             headers: [{"x-cadence-tenant", @organization_id}]
           }
  end
end
