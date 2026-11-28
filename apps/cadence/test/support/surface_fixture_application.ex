defmodule Cadence.TestSupport.SurfaceFixtureApplication do
  @moduledoc """
  A test-only federated application for the console federation smoke (it gates §11c(C)).

  Product applications move and retire; the smoke's contract checks (remote mount, release N-1 →
  N → rollback, cache reuse, CSRF through the console's host bridge, scope changes) need one that
  can't. This is the frontend's `surface_fixture` remote (`frontend/apps/surface-fixture`), known to
  the server only in the test environment, through
  `config :cadence, :fixture_application_contributors` (see
  `Cadence.Applications.FixtureContributors`). Production publication and the release output check
  both forbid the remote, so it can't ship.

  - `mission_surface` (mission scope) shows what the host handed the remote (scope and ids) and
    the release serving it. One surface: activation gives each released surface its own remote.
  - `record_nonce` (mission scope) echoes a nonce. It changes nothing, so a smoke can count
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

  @application_key "surface_fixture"
  @version 1
  @package_id "cadence.surface-fixture"
  @remote_name "cadence_surface_fixture"
  @manifest_path "/assets/application-host/surface-fixture/mf-manifest.json"

  @surfaces [
    %{
      id: "mission_surface",
      scope: :mission,
      query: "cadence.surface_fixture.mission",
      order: 90
    }
  ]

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @application_key,
      version: @version,
      display_name: "Surface Fixture",
      description: "A fixture for the console's federated surface contract.",
      trust: :first_party,
      installation_policy: :platform,
      availability: :available,
      installable_scopes: [:mission],
      actions: [
        %ActionDefinition{
          action_id: "record_nonce",
          version: @version,
          intent: :diagnostic,
          scope: :mission,
          input_contract: %{schema_id: "cadence.surface_fixture.record_nonce.input", version: 1},
          result_contract: %{schema_id: "cadence.surface_fixture.record_nonce.result", version: 1},
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
        release_id: "surface-fixture-v1",
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
        provider: Cadence.TestSupport.SurfaceFixtureApplication.Query
      }
    end)
  end

  @spec action_provider() :: module()
  def action_provider, do: Cadence.TestSupport.SurfaceFixtureApplication.Action

  defp surface(%{id: id, scope: scope, query: query, order: order}) do
    %SurfaceDefinition{
      surface_id: id,
      version: @version,
      purpose: :overview,
      scope: scope,
      placement: :application_workspace,
      navigation: %{label: "Surface fixture", order: order},
      data_contract: %{query_id: query, version: 1},
      actions: if(scope == :mission, do: ["record_nonce"], else: []),
      refresh: :after_action,
      renderer: {:trusted, "cadence.surface_fixture.#{id}"}
    }
  end
end

defmodule Cadence.TestSupport.SurfaceFixtureApplication.Query do
  @moduledoc "The surface fixture's surface reads: the host context it was given, nothing else."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope

  @impl true
  def application_key, do: "surface_fixture"

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host, %SurfaceQueryRequest{} = request) do
    # A trusted surface's result: navigation plus the data the remote reads (as trusted_surface).
    {:ok,
     %{
       "navigation" => %{},
       "data" => %{
         "surface_id" => request.surface_id,
         "placement" => to_string(host.placement),
         "organization_id" => scope.organization_id,
         "mission_id" => host.mission_id,
         "spacecraft_id" => Map.get(host, :spacecraft_id)
       }
     }}
  end
end

defmodule Cadence.TestSupport.SurfaceFixtureApplication.Action do
  @moduledoc "The surface fixture's one action: echoes the nonce, changes nothing."
  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "surface_fixture"

  @impl true
  def execute(_scope, _host, %{action_id: "record_nonce", params: %{"nonce" => nonce}})
      when is_binary(nonce),
      do: {:ok, %{"accepted" => true, "nonce" => nonce}}

  def execute(_scope, _host, _request), do: {:error, :invalid_params}
end
