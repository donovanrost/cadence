defmodule Cadence.Dashboards.SourceRegistry.AdapterOptionsTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.{
    DataSource,
    ResolvedSourceBinding,
    ResolvedSourceCredential,
    SourceCapabilities,
    SourceCredentialMaterial
  }

  alias Cadence.Dashboards.SourceRegistry.AdapterOptions

  test "builds request-local adapter options with capabilities and binding context" do
    resolved_binding = resolved_binding()

    capabilities = %SourceCapabilities{
      logical_source: :telemetry,
      supported_time_axes: [:receipt_time]
    }

    assert {:ok, opts} =
             AdapterOptions.build(
               source_request(),
               resolved_binding,
               [
                 source_opts: %{telemetry: [history_limit: 25]},
                 freshness_policy: %{max_age_ms: 30_000},
                 freshness_now: ~U[2026-07-19 10:00:00Z],
                 persisted?: true
               ],
               capabilities
             )

    assert opts[:history_limit] == 25
    assert opts[:freshness_policy] == %{max_age_ms: 30_000}
    assert opts[:freshness_now] == ~U[2026-07-19 10:00:00Z]
    assert opts[:persisted?]
    assert opts[:source_capabilities] == capabilities
    assert opts[:supported_time_axes] == [:receipt_time]
    assert opts[:source_binding] == resolved_binding
  end

  test "passes secret material to the adapter while keeping its profile redacted" do
    data_source = %DataSource{
      data_source_id: "customer-source",
      owner: :customer,
      kind: :byo_tsdb,
      isolation_level: :customer_owned,
      organization_id: "org-1",
      credentials_ref: "secret://org-1/dashboard/customer-source"
    }

    material =
      SourceCredentialMaterial.new(
        credential(data_source.credentials_ref),
        %{
          http_endpoint: "https://quest.example.test",
          bearer_token: "execution-token",
          headers: [{"x-tenant", "org-1"}]
        }
      )

    opts = AdapterOptions.merge_connection_options([], data_source, material)

    assert opts[:http_endpoint] == "https://quest.example.test"
    assert {"authorization", "Bearer execution-token"} in opts[:headers]
    assert {"x-tenant", "org-1"} in opts[:headers]
    assert opts[:source_connection_material][:bearer_token] == "execution-token"

    profile = Keyword.fetch!(opts, :source_connection_profile)
    assert profile.secret_material?
    assert "bearer_token" in profile.secret_material_fields
    assert "headers" in profile.secret_material_fields
    refute inspect(profile) =~ "execution-token"
  end

  test "uses only safe public connection metadata for descriptor credentials" do
    data_source = %DataSource{
      data_source_id: "customer-source",
      owner: :customer,
      kind: :byo_tsdb,
      isolation_level: :customer_owned,
      organization_id: "org-1",
      credentials_ref: "secret://org-1/dashboard/customer-source",
      metadata: %{http_endpoint: "https://quest.example.test"}
    }

    opts =
      AdapterOptions.merge_connection_options(
        [],
        data_source,
        credential(data_source.credentials_ref)
      )

    assert opts[:http_endpoint] == "https://quest.example.test"
    refute Keyword.has_key?(opts, :headers)
    refute Keyword.has_key?(opts, :source_connection_material)
    refute opts[:source_connection_profile].secret_material?
  end

  defp resolved_binding do
    %ResolvedSourceBinding{
      binding: data_binding("flight-source"),
      data_source: data_source("flight-source", []),
      realm: :flight,
      dataset: "flight"
    }
  end

  defp credential(credentials_ref) do
    %ResolvedSourceCredential{
      credentials_ref: credentials_ref,
      organization_id: "org-1",
      data_source_id: "customer-source",
      owner: :customer,
      kind: :token,
      provider: "test",
      status: :active,
      credential_version: 1,
      secret_material?: false
    }
  end
end
