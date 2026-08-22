defmodule Cadence.Reads.ApplicationSurfaces.ReferenceProviders.CanonicalTelemetryPoints do
  @moduledoc """
  Mission-scoped canonical point choices from active decom and governed derived telemetry.
  """

  @behaviour Cadence.Reads.ApplicationSurfaces.ReferenceProvider

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.Extensions.Presentation.{ReferenceDefinition, ReferenceOption, ReferencePage}
  alias Cadence.Governance
  alias Cadence.Ops.PointCatalog

  @provider_id "cadence.telemetry.canonical_points"

  @impl true
  def search(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id},
        %ReferenceDefinition{provider_id: @provider_id, version: 1},
        query,
        limit
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(query) and
             is_integer(limit) and limit > 0 do
    raw_options =
      organization_id
      |> PointCatalog.list_points(mission_id)
      |> Enum.map(&raw_option/1)

    derived_options =
      mission_id
      |> Governance.list_derived_definitions()
      |> Enum.map(&derived_option/1)

    query = String.trim(query)

    matches =
      (raw_options ++ derived_options)
      |> Enum.reduce(%{}, fn option, by_value ->
        Map.put_new(by_value, option.value, option)
      end)
      |> Map.values()
      |> Enum.sort_by(& &1.value)
      |> Enum.filter(&matches?(&1, query))

    {:ok,
     %ReferencePage{
       query: query,
       options: Enum.take(matches, limit),
       more?: length(matches) > limit
     }}
  end

  def search(%Scope{}, %HostContext{}, %ReferenceDefinition{}, _query, _limit),
    do: {:error, :unsupported_reference_scope}

  defp raw_option(point) do
    %ReferenceOption{
      value: point.point_id,
      label: point.point_id,
      description: raw_description(point)
    }
  end

  defp derived_option(definition) do
    %ReferenceOption{
      value: definition.point_id,
      label: definition.point_id,
      description: derived_description(definition)
    }
  end

  defp raw_description(point) do
    ["Active telemetry", point.description, point.unit && "Unit: #{point.unit}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp derived_description(definition) do
    if definition.point_name == definition.point_id do
      "Derived telemetry"
    else
      "Derived telemetry · #{definition.point_name}"
    end
  end

  defp matches?(_option, ""), do: true

  defp matches?(option, query) do
    normalized_query = String.downcase(query)

    [option.value, option.label, option.description]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(fn candidate ->
      candidate
      |> String.downcase()
      |> String.contains?(normalized_query)
    end)
  end
end
