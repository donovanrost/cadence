defmodule CadenceWeb.OpsDataSourcesLive.SourceRegistrationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDataSourcesLive.SourceRegistration

  test "parses BYO source input and builds persistence payloads" do
    params =
      SourceRegistration.defaults()
      |> Map.merge(%{
        "data_source_id" => " source-1 ",
        "credentials_ref" => " credential-1 ",
        "endpoint_ref" => " endpoint-1 ",
        "material_env_profile" => " flight ",
        "http_endpoint_env" => " QUESTDB_HTTP_ENDPOINT "
      })

    assert {:ok, attrs} = SourceRegistration.parse(params, "org-1", "mission-1")

    assert %{
             data_source_id: "source-1",
             logical_source: :telemetry,
             kind: :byo_tsdb,
             owner: :customer,
             isolation_level: :customer_owned,
             organization_id: "org-1",
             mission_id: "mission-1",
             credentials_ref: "credential-1",
             storage: :questdb
           } = attrs

    source = SourceRegistration.data_source(attrs)

    assert source.adapter == Cadence.Dashboards.Sources.Telemetry
    assert source.capabilities.range_scan?
    assert source.metadata.endpoint_ref == "endpoint-1"
    assert source.metadata.material_env_profile == "flight"

    credential = SourceRegistration.credential_attrs(attrs, %{request_id: "request-1"})

    assert credential.kind == :byo_tsdb_connection
    assert credential.provider == "questdb"
    assert credential.metadata.http_endpoint_env == "QUESTDB_HTTP_ENDPOINT"
    assert credential.payload == %{request_id: "request-1"}
  end

  test "allows managed sources without a credential reference" do
    params =
      SourceRegistration.defaults()
      |> Map.merge(%{
        "data_source_id" => "managed-1",
        "kind" => "managed_tsdb",
        "isolation_level" => "mission_isolated",
        "credentials_ref" => ""
      })

    assert {:ok, %{owner: :cadence, credentials_ref: nil} = attrs} =
             SourceRegistration.parse(params, "org-1", "mission-1")

    assert SourceRegistration.data_source(attrs).kind == :managed_tsdb
  end

  test "rejects missing identifiers, missing BYO credentials, and invalid isolation pairs" do
    defaults = SourceRegistration.defaults()

    assert {:error, "Source ID is required."} =
             SourceRegistration.parse(defaults, "org-1", "mission-1")

    assert {:error, "Credential ref is required for BYO TSDB sources."} =
             defaults
             |> Map.put("data_source_id", "source-1")
             |> SourceRegistration.parse("org-1", "mission-1")

    assert {:error, "Managed TSDB sources cannot use customer_owned isolation."} =
             defaults
             |> Map.merge(%{
               "data_source_id" => "source-1",
               "kind" => "managed_tsdb",
               "credentials_ref" => "credential-1"
             })
             |> SourceRegistration.parse("org-1", "mission-1")
  end

  test "publishes the form's supported option values" do
    assert {"Operational observables", "operational_observables"} in SourceRegistration.logical_source_options()

    assert {"Managed TSDB", "managed_tsdb"} in SourceRegistration.source_kind_options()

    assert {"Mission isolated", "mission_isolated"} in SourceRegistration.source_isolation_options()

    assert {"External vault", "external_vault"} in SourceRegistration.credential_provider_options()

    assert {"Postgres projection", "postgres_projection"} in SourceRegistration.source_storage_options()
  end
end
