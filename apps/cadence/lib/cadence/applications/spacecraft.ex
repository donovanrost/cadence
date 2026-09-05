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
    SurfaceDefinition,
    SurfaceQueryContribution
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
      query_id: "cadence.spacecraft.new",
      actions: ["validate", "save"]
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
      query_id: "cadence.spacecraft.profile.new",
      actions: ["validate", "save"]
    },
    %{
      id: "profile_show",
      scope: :mission,
      purpose: :subject_detail,
      label: "Spacecraft profile",
      order: 50,
      fallback_path: "/missions/:mission_id/spacecraft/profiles/:subject",
      subject_contract: %{schema_id: "cadence.spacecraft.profile.subject", version: 1},
      query_id: "cadence.spacecraft.profile.show"
    },
    %{
      id: "show",
      scope: :spacecraft,
      purpose: :overview,
      label: "Spacecraft overview",
      order: 10,
      fallback_path: "/missions/:mission_id/spacecraft/:subject",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.show"
    },
    %{
      id: "edit",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Edit spacecraft",
      order: 20,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/identity",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.edit",
      actions: ["validate", "save"]
    },
    %{
      id: "readiness",
      scope: :spacecraft,
      purpose: :overview,
      label: "Spacecraft readiness",
      order: 30,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/readiness",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.readiness"
    },
    %{
      id: "routing",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Spacecraft routing",
      order: 40,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/routing",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.routing"
    },
    %{
      id: "commanding",
      scope: :spacecraft,
      purpose: :operations,
      label: "Spacecraft commanding",
      order: 50,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/commanding",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.commanding"
    },
    %{
      id: "applications",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Spacecraft applications",
      order: 60,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/applications",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.spacecraft.applications",
      actions: ["install", "disable", "uninstall"]
    },
    %{
      id: "telemetry_decom",
      scope: :spacecraft,
      purpose: :configuration,
      label: "Telemetry decomposition",
      order: 70,
      fallback_path: "/missions/:mission_id/spacecraft/:subject/applications/telemetry_decom",
      subject_contract: %{schema_id: "cadence.spacecraft.subject", version: 1},
      query_id: "cadence.telemetry_decom.manage",
      actions: ["save_configuration", "request_activation", "disable"]
    }
  ]

  @doc "Returns the stable identity shared by the catalog, release, and frontend manifest."
  def identity, do: @identity

  @doc "Returns the Phoenix-owned application definition for Spacecraft surfaces."
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: 1,
      display_name: "Spacecraft",
      description: "Mission spacecraft configuration and operations surfaces.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission, :spacecraft],
      actions: action_definitions(),
      surfaces: Enum.map(@surface_specs, &surface_definition/1)
    }
  end

  @doc "Returns the query contributions owned by the Spacecraft application lane."
  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions,
    do: Cadence.Reads.ApplicationSurfaces.Spacecraft.contributions()

  @doc "Returns the action provider for Spacecraft-owned remote actions."
  def action_provider, do: Cadence.Applications.Spacecraft.ActionProvider

  @doc "Returns one release contribution for every exposed federated surface."
  def release_contributions do
    Enum.map(@surface_specs, fn spec ->
      %ReleaseContribution{
        application_key: @identity.application_key,
        application_version: 1,
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
      placement: :application_workspace,
      navigation: %{label: spec.label, order: spec.order, fallback_path: spec.fallback_path},
      subject_contract: Map.get(spec, :subject_contract),
      data_contract: %{query_id: spec.query_id, version: 1},
      actions: Map.get(spec, :actions, []),
      renderer: {:trusted, "cadence.spacecraft.#{spec.id}"}
    }
  end

  defp action_definitions do
    [
      %ActionDefinition{
        action_id: "validate",
        version: 1,
        intent: :diagnostic,
        scope: :mission,
        required_permission: "operate_mission",
        effect: :none,
        execution: :immediate,
        input_contract: %{schema_id: "cadence.spacecraft.form", version: 1},
        result_contract: %{schema_id: "cadence.spacecraft.validation", version: 1}
      },
      %ActionDefinition{
        action_id: "save",
        version: 1,
        intent: :configuration,
        scope: :mission,
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        input_contract: %{schema_id: "cadence.spacecraft.form", version: 1},
        result_contract: %{schema_id: "cadence.spacecraft.saved", version: 1}
      },
      %ActionDefinition{
        action_id: "install",
        version: 1,
        intent: :configuration,
        scope: :spacecraft,
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        input_contract: %{
          schema_id: "cadence.spacecraft.child_application_action",
          version: 1
        },
        result_contract: %{
          schema_id: "cadence.spacecraft.child_application_action_result",
          version: 1
        }
      },
      %ActionDefinition{
        action_id: "disable",
        version: 1,
        intent: :configuration,
        scope: :spacecraft,
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        input_contract: %{
          schema_id: "cadence.spacecraft.child_application_action",
          version: 1
        },
        result_contract: %{
          schema_id: "cadence.spacecraft.child_application_action_result",
          version: 1
        }
      },
      %ActionDefinition{
        action_id: "uninstall",
        version: 1,
        intent: :configuration,
        scope: :spacecraft,
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        input_contract: %{
          schema_id: "cadence.spacecraft.child_application_action",
          version: 1
        },
        result_contract: %{
          schema_id: "cadence.spacecraft.child_application_action_result",
          version: 1
        }
      },
      %ActionDefinition{
        action_id: "save_configuration",
        version: 1,
        intent: :configuration,
        scope: :spacecraft,
        required_permission: "operate_mission",
        effect: :durable,
        execution: :immediate,
        input_contract: %{
          schema_id: "cadence.telemetry_decom.configuration_input",
          version: 1
        },
        result_contract: %{
          schema_id: "cadence.telemetry_decom.configuration",
          version: 1
        }
      },
      %ActionDefinition{
        action_id: "request_activation",
        version: 1,
        intent: :operation,
        scope: :spacecraft,
        required_permission: "request_activation",
        effect: :durable,
        execution: :approval_required,
        input_contract: %{
          schema_id: "cadence.telemetry_decom.activation_input",
          version: 1
        },
        result_contract: %{
          schema_id: "cadence.telemetry_decom.activation_request",
          version: 1
        }
      }
    ]
  end
end
