defmodule Cadence.TestSupport.ContractProbeApplication do
  @moduledoc """
  A test-only federated application for the console federation smoke (it gates §11c(C)).

  Product applications move and retire; the smoke's contract checks (remote mount, release N-1 →
  N → rollback, cache reuse, CSRF through the console's host bridge, scope changes) need one that
  can't. This is the frontend's `contract_probe` remote (`frontend/apps/contract-probe`), known to
  the server only in the test environment, through
  `config :cadence, :fixture_application_contributors` (see
  `Cadence.Applications.FixtureContributors`). Production publication and the release output check
  both forbid the remote, so it can't ship.

  - `mission_contracts` (mission scope) and `spacecraft_contracts` (spacecraft scope) show what the
    host handed the remote (scope and ids) and the release serving it.
  - `record_probe` (mission scope) echoes a nonce. It changes nothing, so a smoke can count
    requests without side effects.
  """

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition,
    SurfaceQueryContribution
  }

  @application_key "contract_probe"
  @version 1
  @package_id "cadence.frontend-fixtures"
  @remote_name "cadence_contract_probe"
  @manifest_path "/assets/application-host/contract-probe/mf-manifest.json"

  @surfaces [
    %{
      id: "mission_contracts",
      scope: :mission,
      query: "cadence.contract_probe.mission",
      order: 90
    },
    %{
      id: "spacecraft_contracts",
      scope: :spacecraft,
      query: "cadence.contract_probe.spacecraft",
      order: 91
    }
  ]

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @application_key,
      version: @version,
      display_name: "Contract Probe",
      description: "A test fixture for the console's federated surface contract.",
      trust: :first_party,
      installation_policy: :platform,
      availability: :available,
      installable_scopes: [:mission, :spacecraft],
      actions: [
        %ActionDefinition{
          action_id: "record_probe",
          version: @version,
          intent: :diagnostic,
          scope: :mission,
          input_contract: %{schema_id: "cadence.contract_probe.record_probe.input", version: 1},
          result_contract: %{schema_id: "cadence.contract_probe.record_probe.result", version: 1},
          required_permission: "operate_mission",
          effect: :none,
          execution: :immediate,
          concurrency: %{strategy: :expected_version}
        }
      ],
      surfaces: Enum.map(@surfaces, &surface/1)
    }
  end

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @package_id,
        package_version: @version
      }
    ]
  end

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    Enum.map(@surfaces, fn surface ->
      %ReleaseContribution{
        application_key: @application_key,
        application_version: @version,
        surface_id: surface.id,
        surface_version: @version,
        federation: :module_federation,
        release_id: "contract-probe-v1",
        remote_name: @remote_name,
        manifest_path: @manifest_path,
        exposed_module: "./Application"
      }
    end)
  end

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    Enum.map(@surfaces, fn surface ->
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: @version,
        query_id: surface.query,
        query_version: 1,
        provider: Cadence.TestSupport.ContractProbeApplication.Query
      }
    end)
  end

  @spec action_provider() :: module()
  def action_provider, do: Cadence.TestSupport.ContractProbeApplication.Action

  defp surface(%{id: id, scope: scope, query: query, order: order}) do
    %SurfaceDefinition{
      surface_id: id,
      version: @version,
      purpose: :overview,
      scope: scope,
      placement: :application_workspace,
      navigation: %{label: "Contract probe", order: order},
      data_contract: %{query_id: query, version: 1},
      actions: if(scope == :mission, do: ["record_probe"], else: []),
      refresh: :after_action,
      renderer: {:trusted, "cadence.contract_probe.#{id}"}
    }
  end
end

defmodule Cadence.TestSupport.ContractProbeApplication.Query do
  @moduledoc "The contract probe's surface reads: the host context it was given, nothing else."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope

  @impl true
  def application_key, do: "contract_probe"

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host, %SurfaceQueryRequest{} = request) do
    {:ok,
     %{
       "surface_id" => request.surface_id,
       "placement" => to_string(host.placement),
       "organization_id" => scope.organization_id,
       "mission_id" => host.mission_id,
       "spacecraft_id" => Map.get(host, :spacecraft_id)
     }}
  end
end

defmodule Cadence.TestSupport.ContractProbeApplication.Action do
  @moduledoc "The contract probe's one action: echoes the nonce, changes nothing."
  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "contract_probe"

  @impl true
  def execute(_scope, _host, %{action_id: "record_probe", params: %{"nonce" => nonce}})
      when is_binary(nonce),
      do: {:ok, %{"accepted" => true, "nonce" => nonce}}

  def execute(_scope, _host, _request), do: {:error, :invalid_params}
end
