defmodule Cadence.Applications.OpsConsole do
  @moduledoc "The first-party contribution boundary for the federated Ops Console."

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition,
    SurfaceQueryContribution
  }

  @identity %{
    application_key: "ops_console",
    application_version: 1,
    package_id: "cadence.ops_console",
    package_version: 1,
    surface_version: 1,
    release_id: "ops-console-v1",
    remote_name: "cadence_ops_console",
    manifest_path: "/assets/application-host/ops-console/mf-manifest.json",
    exposed_module: "./Application"
  }

  @ops_actions [
    "validate",
    "save",
    "filter",
    "refresh",
    "select",
    "open_data_link",
    "open_evidence",
    "set_chart_time_range"
  ]

  @surface_specs [
    %{
      id: "workspace",
      purpose: :overview,
      placement: :application_workspace,
      label: "Ops Console",
      order: 10,
      query_id: "cadence.ops.workspace",
      actions: [],
      fallback_path: "/missions/:mission_id/ops"
    },
    %{
      id: "ops",
      purpose: :operations,
      placement: :ops_workspace,
      label: "Operations",
      order: 10,
      query_id: "cadence.ops.console",
      actions: @ops_actions,
      fallback_path: "/missions/:mission_id/ops"
    }
  ]

  @spec identity() :: map()
  def identity, do: @identity

  @spec surface_ids() :: [binary()]
  def surface_ids, do: Enum.map(@surface_specs, & &1.id)

  @spec application_key() :: binary()
  def application_key, do: @identity.application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.OpsConsole.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    Enum.map(@surface_specs, fn spec ->
      %SurfaceQueryContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        query_id: spec.query_id,
        query_version: @identity.surface_version,
        provider: Cadence.Reads.ApplicationSurfaces.OpsConsole
      }
    end)
  end

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    Enum.map(@surface_specs, fn spec ->
      %ReleaseContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        surface_id: spec.id,
        surface_version: @identity.surface_version,
        federation: :module_federation,
        release_id: @identity.release_id,
        remote_name: @identity.remote_name,
        manifest_path: @identity.manifest_path,
        exposed_module: @identity.exposed_module
      }
    end)
  end

  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @identity.package_id,
        package_version: @identity.package_version
      }
    ]
  end

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Ops Console",
      description: "Mission operations, dashboard runtime, evidence, and control surfaces.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      actions: action_definitions(),
      surfaces: Enum.map(@surface_specs, &surface_definition/1)
    }
  end

  defp surface_definition(spec) do
    %SurfaceDefinition{
      surface_id: spec.id,
      version: @identity.surface_version,
      purpose: spec.purpose,
      scope: :mission,
      placement: spec.placement,
      navigation: %{
        label: spec.label,
        order: spec.order,
        fallback_path: spec.fallback_path
      },
      data_contract: %{query_id: spec.query_id, version: @identity.surface_version},
      actions: spec.actions,
      refresh: :static,
      renderer: {:trusted, "cadence.ops.console"}
    }
  end

  defp action_definitions do
    Enum.map(@ops_actions, fn action_id ->
      %ActionDefinition{
        action_id: action_id,
        version: @identity.application_version,
        intent: :operation,
        scope: :mission,
        input_contract: %{schema_id: "cadence.ops_console.#{action_id}.input", version: 1},
        result_contract: %{schema_id: "cadence.ops_console.#{action_id}.result", version: 1},
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        concurrency: %{strategy: :expected_version}
      }
    end)
  end
end
