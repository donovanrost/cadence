defmodule Cadence.Applications.Comms do
  @moduledoc "The single source of truth for the first-party Comms application contract."

  alias Cadence.Applications.{ApplicationDefinition, SurfaceDefinition}

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
    }
  ]

  @spec identity() :: map()
  def identity, do: @identity

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

  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @identity.application_key,
      version: @identity.application_version,
      display_name: "Communications",
      description: "Inspect mission-scoped communications setup and validation.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:mission],
      resource_contract: %Cadence.Applications.ResourceContract{},
      lifecycle_contract: %Cadence.Applications.LifecycleContract{},
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
      actions: [],
      refresh: :static,
      renderer: {:trusted, "cadence.comms." <> spec.id}
    }
  end

  defp subject_contract(%{subject_schema: schema}),
    do: %{schema_id: schema, version: @identity.surface_version}

  defp subject_contract(_spec), do: nil
end
