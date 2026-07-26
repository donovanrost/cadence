defmodule Cadence.Applications.Registry do
  @moduledoc """
  Tolerant registry of compiled first-party product applications.

  Durable application and renderer identifiers remain strings. Registry lookup
  never converts operator-controlled input into atoms.
  """

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    LifecycleContract,
    ResourceClaimDefinition,
    ResourceContract,
    StatusPlacement,
    SurfaceDefinition
  }

  alias Cadence.Extensions.Presentation.ReferenceDefinition

  @type fetch_error ::
          :unknown_application
          | :unsupported_application_version
          | :invalid_application_definition
  @type surface_error :: :unknown_surface | :invalid_application_definition

  @spec all() :: [ApplicationDefinition.t()]
  def all, do: [telemetry_decom(), derived_telemetry(), limits(), cfdp()]

  @spec available() :: [ApplicationDefinition.t()]
  def available do
    Enum.filter(all(), fn definition ->
      ApplicationDefinition.available?(definition) and
        ApplicationDefinition.validate(definition) == :ok
    end)
  end

  @spec available_for_scope(ApplicationDefinition.scope()) :: [ApplicationDefinition.t()]
  def available_for_scope(scope) do
    Enum.filter(available(), &(scope in &1.installable_scopes))
  end

  @spec known_keys() :: [binary()]
  def known_keys, do: Enum.map(all(), & &1.application_key)

  @spec fetch(binary(), pos_integer() | :latest | nil) ::
          {:ok, ApplicationDefinition.t()} | {:error, fetch_error()}
  def fetch(application_key, version \\ :latest)

  def fetch(application_key, version) when is_binary(application_key) do
    case Map.fetch(definitions(), application_key) do
      {:ok, %ApplicationDefinition{} = definition}
      when version in [:latest, nil, definition.version] ->
        case ApplicationDefinition.validate(definition) do
          :ok -> {:ok, definition}
          {:error, :invalid_application_definition} -> {:error, :invalid_application_definition}
        end

      {:ok, %ApplicationDefinition{}} ->
        {:error, :unsupported_application_version}

      :error ->
        {:error, :unknown_application}
    end
  end

  def fetch(_application_key, _version), do: {:error, :unknown_application}

  @spec fetch_available(binary(), pos_integer() | :latest | nil) ::
          {:ok, ApplicationDefinition.t()} | {:error, fetch_error() | :application_unavailable}
  def fetch_available(application_key, version \\ :latest) do
    with {:ok, definition} <- fetch(application_key, version),
         true <- ApplicationDefinition.available?(definition) do
      {:ok, definition}
    else
      false -> {:error, :application_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_default_surface(ApplicationDefinition.t(), SurfaceDefinition.scope()) ::
          {:ok, SurfaceDefinition.t()} | {:error, surface_error()}
  def fetch_default_surface(%ApplicationDefinition{} = definition, scope) do
    with :ok <- ApplicationDefinition.validate(definition) do
      case List.first(workspace_surfaces(definition, scope)) do
        %SurfaceDefinition{} = surface -> {:ok, surface}
        nil -> {:error, :unknown_surface}
      end
    end
  end

  @spec fetch_surface(ApplicationDefinition.t(), SurfaceDefinition.scope(), binary()) ::
          {:ok, SurfaceDefinition.t()} | {:error, surface_error()}
  def fetch_surface(%ApplicationDefinition{} = definition, scope, surface_id)
      when is_binary(surface_id) do
    with :ok <- ApplicationDefinition.validate(definition) do
      case Enum.find(workspace_surfaces(definition, scope), &(&1.surface_id == surface_id)) do
        %SurfaceDefinition{} = surface -> {:ok, surface}
        nil -> {:error, :unknown_surface}
      end
    end
  end

  def fetch_surface(%ApplicationDefinition{}, _scope, _surface_id),
    do: {:error, :unknown_surface}

  @spec workspace_surfaces(ApplicationDefinition.t(), SurfaceDefinition.scope()) ::
          [SurfaceDefinition.t()]
  def workspace_surfaces(%ApplicationDefinition{} = definition, scope) do
    if ApplicationDefinition.validate(definition) == :ok do
      definition.surfaces
      |> Enum.filter(fn surface ->
        surface.scope == scope and surface.placement == :application_workspace
      end)
      |> Enum.sort_by(fn surface ->
        {Map.get(surface.navigation, :order, 0), surface.surface_id}
      end)
    else
      []
    end
  end

  defp definitions do
    Map.new(all(), &{&1.application_key, &1})
  end

  defp telemetry_decom do
    %ApplicationDefinition{
      application_key: "telemetry_decom",
      version: 1,
      display_name: "Telemetry Decom",
      description: "Claim packet APIDs and decode selected packets into named telemetry points.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:spacecraft],
      configuration_contract: %{
        schema_id: "cadence.telemetry_decom.configuration",
        version: 1
      },
      resource_contract: %ResourceContract{
        claims: [
          %ResourceClaimDefinition{
            claim_type: :packet_apid,
            scope: :spacecraft,
            mode: :exclusive,
            description: "Packet APIDs handled by this spacecraft application."
          }
        ]
      },
      lifecycle_contract: %LifecycleContract{
        actions: ["save_configuration", "request_activation", "disable"]
      },
      status_query_id: "cadence.telemetry_decom.status",
      status_placements: [
        %StatusPlacement{
          placement: :comms_validation,
          scope: :spacecraft,
          required?: true
        }
      ],
      preflight_query_id: "cadence.telemetry_decom.activation_preflight",
      capability_contributions: [
        %{kind: :semantic_handler, family_key: :definition_bound_telemetry}
      ],
      surfaces: [
        %SurfaceDefinition{
          surface_id: "manage",
          version: 1,
          purpose: :configuration,
          scope: :spacecraft,
          placement: :application_workspace,
          navigation: %{label: "Manage", order: 10},
          data_contract: %{
            query_id: "cadence.telemetry_decom.manage",
            version: 1
          },
          references: %{
            "catalog_revision_id" => %ReferenceDefinition{
              provider_id: "cadence.catalog.telemetry_revisions",
              version: 1
            }
          },
          actions: ["save_configuration", "request_activation", "disable"],
          refresh: :after_action,
          renderer: {:trusted, "cadence.telemetry_decom.manage"}
        }
      ]
    }
  end

  defp derived_telemetry do
    %ApplicationDefinition{
      application_key: "derived_telemetry",
      version: 1,
      display_name: "Derived Telemetry",
      description: "Define and observe calculated telemetry points from canonical mission data.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      configuration_contract: %{
        schema_id: "cadence.derived_telemetry.definition",
        version: 1
      },
      resource_contract: %ResourceContract{},
      lifecycle_contract: %LifecycleContract{},
      status_query_id: "cadence.derived_telemetry.status",
      actions: [
        %ActionDefinition{
          action_id: "save_definition",
          version: 1,
          intent: :configuration,
          scope: :mission,
          input_contract: %{
            schema_id: "cadence.derived_telemetry.definition_input",
            version: 1
          },
          result_contract: %{
            schema_id: "cadence.derived_telemetry.definition",
            version: 1
          },
          required_permission: "operate_mission",
          effect: :durable,
          execution: :immediate,
          concurrency: %{strategy: :append_version}
        }
      ],
      surfaces: [
        %SurfaceDefinition{
          surface_id: "manage",
          version: 1,
          purpose: :configuration,
          scope: :mission,
          placement: :application_workspace,
          navigation: %{label: "Manage", order: 10},
          data_contract: %{
            query_id: "cadence.derived_telemetry.manage",
            version: 1
          },
          actions: ["save_definition"],
          refresh: :after_action,
          renderer: {:declarative, "cadence.host.surface.v1"}
        }
      ],
      capability_contributions: [
        %{kind: :projection, family_key: :derived_telemetry}
      ]
    }
  end

  defp limits do
    %ApplicationDefinition{
      application_key: "limits",
      version: 1,
      display_name: "Limits & Alarming",
      description: "Govern telemetry thresholds and inspect the mission's current limit posture.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      configuration_contract: %{
        schema_id: "cadence.limits.definition",
        version: 1
      },
      resource_contract: %ResourceContract{
        claims: [
          %ResourceClaimDefinition{
            claim_type: :canonical_point,
            scope: :mission,
            mode: :shared,
            description: "Canonical telemetry points referenced by governed limit definitions."
          }
        ]
      },
      lifecycle_contract: %LifecycleContract{},
      status_query_id: "cadence.limits.status",
      actions: [
        %ActionDefinition{
          action_id: "save_limit_definition",
          version: 1,
          intent: :configuration,
          scope: :mission,
          input_contract: %{
            schema_id: "cadence.limits.definition_input",
            version: 1
          },
          result_contract: %{
            schema_id: "cadence.limits.definition",
            version: 1
          },
          required_permission: "operate_mission",
          effect: :durable,
          execution: :immediate,
          concurrency: %{strategy: :append_version}
        }
      ],
      surfaces: [
        %SurfaceDefinition{
          surface_id: "manage",
          version: 1,
          purpose: :configuration,
          scope: :mission,
          placement: :application_workspace,
          navigation: %{label: "Definitions", order: 10},
          data_contract: %{
            query_id: "cadence.limits.manage",
            version: 1
          },
          references: %{
            "point_id" => %ReferenceDefinition{
              provider_id: "cadence.telemetry.canonical_points",
              version: 1,
              mode: :search,
              result_limit: 20
            }
          },
          actions: ["save_limit_definition"],
          refresh: :after_action,
          renderer: {:declarative, "cadence.host.surface.v1"}
        },
        %SurfaceDefinition{
          surface_id: "activity",
          version: 1,
          purpose: :activity,
          scope: :mission,
          placement: :application_workspace,
          navigation: %{label: "Current posture", order: 20},
          data_contract: %{
            query_id: "cadence.limits.activity",
            version: 1
          },
          actions: [],
          refresh: :static,
          renderer: {:declarative, "cadence.host.surface.v1"}
        }
      ],
      capability_contributions: [
        %{kind: :projection, family_key: :limits}
      ]
    }
  end

  defp cfdp do
    %ApplicationDefinition{
      application_key: "cfdp",
      version: 1,
      display_name: "CFDP",
      description: "Transfer files using the CCSDS File Delivery Protocol.",
      trust: :first_party,
      availability: :roadmap,
      installable_scopes: [:mission],
      configuration_contract: %{
        schema_id: "cadence.cfdp.configuration",
        version: 1
      },
      resource_contract: %ResourceContract{
        claims: [
          %ResourceClaimDefinition{
            claim_type: :source_endpoint,
            scope: :mission,
            mode: :reference,
            description: "Ingress and egress endpoints used by CFDP entities."
          },
          %ResourceClaimDefinition{
            claim_type: :transport,
            scope: :mission,
            mode: :reference,
            description: "Mission transports selected for CFDP protocol traffic."
          }
        ]
      },
      lifecycle_contract: %LifecycleContract{},
      capability_contributions: [
        %{
          kind: :managed_application,
          family_key: :cfdp_receive,
          scope: :source_endpoint,
          maturity: :runtime_proof
        }
      ]
    }
  end
end
