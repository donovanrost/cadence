defmodule Cadence.Applications.Spacecraft do
  @moduledoc """
  Domain-owned application contract for the federated Spacecraft surfaces.

  The release contributions describe the approved remote artifact while the
  catalog contribution preserves the Phoenix-owned application definition.
  The central registries may compose this module during the later cutover.
  """

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition
  }

  @identity %{
    application_key: "spacecraft",
    package_id: "cadence.spacecraft",
    package_version: 1,
    remote_name: "cadence_spacecraft",
    manifest_path: "/assets/application-host/spacecraft/mf-manifest.json",
    exposed_module: "./Application"
  }

  @surface_specs [
    %{
      id: "list",
      scope: :mission,
      purpose: :overview,
      label: "Spacecraft",
      order: 10,
      fallback_path: "/missions/:mission_id/spacecraft",
      query_id: "cadence.spacecraft.list"
    },
    %{
      id: "new",
      scope: :mission,
      purpose: :configuration,
      label: "New spacecraft",
      order: 20,
      fallback_path: "/missions/:mission_id/spacecraft/new",
      query_id: "cadence.spacecraft.new"
    },
    %{
      id: "profile_list",
      scope: :mission,
      purpose: :overview,
      label: "Spacecraft profiles",
      order: 30,
      fallback_path: "/missions/:mission_id/spacecraft/profiles",
      query_id: "cadence.spacecraft.profiles"
    },
    %{
      id: "profile_new",
      scope: :mission,
      purpose: :configuration,
      label: "New spacecraft profile",
      order: 40,
      fallback_path: "/missions/:mission_id/spacecraft/profiles/new",
      query_id: "cadence.spacecraft.profile.new"
    },
    %{
      id: "profile_show",
      scope: :mission,
      purpose: :subject_detail,
      label: "Spacecraft profile",
      order: 50,
      fallback_path: "/missions/:mission_id/spacecraft/profiles/:subject",
      subject_contract: %{id: "cadence.spacecraft.profile.subject", version: 1},
      query_id: "cadence.spacecraft.profile.show"
    },
    %{
      id: "show",
      scope: :spacecraft,
      purpose: :overview,
      label: "Spacecraft overview",
      order: 10,
      fallback_path: "/missions/:mission_id/spacecraft/:subject",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.show"
    },
    %{
      id: "edit",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Edit spacecraft",
      order: 20,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/identity",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.edit"
    },
    %{
      id: "readiness",
      scope: :spacecraft,
      purpose: :overview,
      label: "Spacecraft readiness",
      order: 30,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/readiness",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.readiness"
    },
    %{
      id: "routing",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Spacecraft routing",
      order: 40,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/routing",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.routing"
    },
    %{
      id: "commanding",
      scope: :spacecraft,
      purpose: :operations,
      label: "Spacecraft commanding",
      order: 50,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/commanding",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.commanding"
    },
    %{
      id: "applications",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Spacecraft applications",
      order: 60,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/applications",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.applications"
    },
    %{
      id: "telemetry_decom",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Telemetry decomposition",
      order: 70,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/applications/telemetry_decom",
      subject_contract: %{id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.telemetry_decom.manage"
    }
  ]

  @doc "Returns the stable identity shared by the catalog, release, and frontend manifest."
  def identity, do: @identity

  @doc "Returns the Phoenix-owned application definition for Spacecraft surfaces."
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      package_id: @identity.package_id,
      package_version: @identity.package_version,
      display_name: "Spacecraft",
      description: "Mission spacecraft configuration and operations surfaces.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission, :spacecraft],
      actions: [],
      surfaces: Enum.map(@surface_specs, &surface_definition/1)
    }
  end

  @doc "Returns one release contribution for every exposed federated surface."
  def release_contributions do
    Enum.map(@surface_specs, fn spec ->
      %ReleaseContribution{
        application_key: @identity.application_key,
        package_id: @identity.package_id,
        package_version: @identity.package_version,
        release_id: "spacecraft-v1",
        federation: :module_federation,
        remote_name: @identity.remote_name,
        manifest_path: @identity.manifest_path,
        exposed_module: @identity.exposed_module,
        surface_id: spec.id,
        surface_version: 1
      }
    end)
  end

  @doc "Returns the catalog contribution that publishes the complete surface definition."
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @identity.package_id,
        package_version: @identity.package_version
      }
    ]
  end

  defp surface_definition(spec) do
    %SurfaceDefinition{
      surface_id: spec.id,
      version: 1,
      scope: spec.scope,
      purpose: spec.purpose,
      navigation: %{label: spec.label, order: spec.order, fallback_path: spec.fallback_path},
      subject_contract: Map.get(spec, :subject_contract),
      data_contract: %{query_id: spec.query_id, version: 1},
      actions: [],
      renderer: {:trusted, "cadence.spacecraft.#{spec.id}"}
    }
  end
end
