defmodule Cadence.Applications.Comms do
  @moduledoc "The single source of truth for the first-party Comms application contract."

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition,
    SurfaceQueryContribution
  }

  @identity %{
    application_key: "comms",
    application_version: 1,
    package_id: "cadence.comms",
    package_version: 1,
    surface_version: 1,
    release_id: "comms-v1",
    remote_name: "cadence_comms",
    manifest_path: "/assets/application-host/comms/mf-manifest.json",
    exposed_module: "./Application"
  }

  @surface_specs [
    %{id: "overview", purpose: :overview, label: "Overview", order: 10, fallback_path: "/comms"},
    %{
      id: "validation",
      purpose: :activity,
      label: "Validation",
      order: 20,
      fallback_path: "/comms/validation"
    },
    %{
      id: "transports",
      purpose: :collection,
      label: "Transports",
      order: 30,
      fallback_path: "/comms/transports"
    },
    %{
      id: "transport",
      purpose: :subject_detail,
      label: "Transport",
      order: 40,
      subject_schema: "cadence.comms.transport.subject",
      fallback_path: "/comms/transports/:subject",
      fallback_parent_path: "/comms/transports"
    },
    %{
      id: "routing",
      purpose: :collection,
      label: "Routing",
      order: 50,
      fallback_path: "/comms/routing"
    },
    %{
      id: "routing_detail",
      purpose: :subject_detail,
      label: "Routing Rule",
      order: 60,
      subject_schema: "cadence.comms.routing_rule.subject",
      fallback_path: "/comms/routing/:subject",
      fallback_parent_path: "/comms/routing"
    },
    %{
      id: "ground_stations",
      purpose: :collection,
      label: "Ground Stations",
      order: 70,
      fallback_path: "/comms/ground-stations"
    },
    %{
      id: "ground_station",
      purpose: :subject_detail,
      label: "Ground Station",
      order: 80,
      subject_schema: "cadence.comms.ground_station.subject",
      fallback_path: "/comms/ground-stations/:subject",
      fallback_parent_path: "/comms/ground-stations"
    },
    %{
      id: "provider_list",
      purpose: :collection,
      label: "Providers",
      order: 90,
      fallback_path: "/comms/providers"
    },
    %{
      id: "provider_new",
      purpose: :configuration,
      label: "New Provider",
      order: 100,
      fallback_path: "/comms/providers/new",
      fallback_parent_path: "/comms/providers"
    },
    %{
      id: "provider_show",
      purpose: :subject_detail,
      label: "Provider",
      order: 110,
      subject_schema: "cadence.comms.provider.subject",
      fallback_path: "/comms/providers/:subject",
      fallback_parent_path: "/comms/providers"
    },
    %{
      id: "transport_new",
      purpose: :configuration,
      label: "New Transport",
      order: 120,
      fallback_path: "/comms/transports/new",
      fallback_parent_path: "/comms/transports"
    },
    %{
      id: "routing_new",
      purpose: :configuration,
      label: "New Routing Rule",
      order: 130,
      fallback_path: "/comms/routing/new",
      fallback_parent_path: "/comms/routing"
    },
    %{
      id: "ground_station_new",
      purpose: :configuration,
      label: "New Ground Station",
      order: 140,
      fallback_path: "/comms/ground-stations/new",
      fallback_parent_path: "/comms/ground-stations"
    },
    %{
      id: "ground_station_edit",
      purpose: :configuration,
      label: "Edit Ground Station",
      order: 150,
      subject_schema: "cadence.comms.ground_station.subject",
      fallback_path: "/comms/ground-stations/:subject/edit",
      fallback_parent_path: "/comms/ground-stations"
    }
  ]

  @provider_actions [
    %{id: "create_provider", surface: "provider_new", effect: :durable},
    %{id: "validate_provider", surface: "provider_show", effect: :external},
    %{id: "sync_provider", surface: "provider_show", effect: :external},
    %{id: "archive_provider", surface: "provider_show", effect: :durable},
    %{
      id: "validate",
      surfaces: ~w(transport_new routing_new ground_station_new ground_station_edit),
      effect: :none
    },
    %{
      id: "save",
      surfaces: ~w(transport_new routing_new ground_station_new ground_station_edit),
      effect: :durable
    }
  ]

  @spec identity() :: map()
  def identity, do: @identity

  @spec application_key() :: binary()
  def application_key, do: @identity.application_key

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

  @spec surface_ids() :: [binary()]
  def surface_ids, do: Enum.map(@surface_specs, & &1.id)

  @spec query_id(binary()) :: {:ok, binary()} | :error
  def query_id(surface_id) when is_binary(surface_id) do
    case Enum.find(@surface_specs, &(&1.id == surface_id)) do
      %{id: id} -> {:ok, "cadence.comms." <> id}
      nil -> :error
    end
  end

  def query_id(_surface_id), do: :error

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    Enum.map(@surface_specs, fn spec ->
      %SurfaceQueryContribution{
        application_key: @identity.application_key,
        application_version: @identity.application_version,
        query_id: "cadence.comms." <> spec.id,
        query_version: @identity.surface_version,
        provider: query_provider(spec.id)
      }
    end)
  end

  @spec host_query_providers() :: [module()]
  def host_query_providers, do: [Cadence.Applications.LegacyCommsOverview.QueryProvider]

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.Comms.ActionProvider

  defp query_provider(surface_id) when surface_id in ~w(provider_list provider_new provider_show),
    do: Cadence.Reads.ApplicationSurfaces.CommsProviders

  defp query_provider(_surface_id), do: Cadence.Reads.ApplicationSurfaces.Comms

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Communications",
      description: "Inspect mission-scoped communications setup and validation.",
      trust: :first_party,
      installation_policy: :platform,
      availability: :available,
      installable_scopes: [:mission],
      resource_contract: %Cadence.Applications.ResourceContract{},
      lifecycle_contract: %Cadence.Applications.LifecycleContract{},
      actions: Enum.map(@provider_actions, &action_definition/1),
      surfaces: Enum.map(@surface_specs, &surface_definition/1)
    }
  end

  defp surface_definition(spec) do
    %SurfaceDefinition{
      surface_id: spec.id,
      version: @identity.surface_version,
      purpose: spec.purpose,
      scope: :mission,
      placement: :application_workspace,
      subject_contract: subject_contract(spec),
      navigation: %{
        label: spec.label,
        order: spec.order,
        fallback_path: Map.get(spec, :fallback_path),
        fallback_parent_path: Map.get(spec, :fallback_parent_path)
      },
      data_contract: %{query_id: "cadence.comms." <> spec.id, version: @identity.surface_version},
      actions: surface_actions(spec.id),
      refresh: :static,
      renderer: {:trusted, "cadence.comms." <> spec.id}
    }
  end

  defp subject_contract(%{subject_schema: schema}),
    do: %{schema_id: schema, version: @identity.surface_version}

  defp subject_contract(_spec), do: nil

  defp surface_actions(surface_id) do
    @provider_actions
    |> Enum.filter(fn action ->
      Map.get(action, :surface) == surface_id or surface_id in Map.get(action, :surfaces, [])
    end)
    |> Enum.map(& &1.id)
  end

  defp action_definition(spec) do
    %ActionDefinition{
      action_id: spec.id,
      version: @identity.application_version,
      intent:
        if(spec.id in ["create_provider", "validate", "save"],
          do: :configuration,
          else: :operation
        ),
      scope: :mission,
      input_contract: %{schema_id: "cadence.comms.#{spec.id}.input", version: 1},
      result_contract: %{schema_id: "cadence.comms.#{spec.id}.result", version: 1},
      required_permission: "operate_mission",
      effect: spec.effect,
      execution: :immediate,
      concurrency: %{strategy: :expected_version}
    }
  end
end
