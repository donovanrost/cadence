defmodule Cadence.Reads.ApplicationSurfaces.ReferenceProviders.CanonicalTelemetryPoints do
  @moduledoc """
  Mission-scoped canonical point choices from the operator point catalog: the active decom's packet
  fields and the active revision's derived parameters (#451 T4b, T4d). A derived point's value is
  its parameter's semantic id, labelled by its qualified name.
  """

  @behaviour Cadence.Reads.ApplicationSurfaces.ReferenceProvider

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.Extensions.Presentation.{ReferenceDefinition, ReferenceOption, ReferencePage}
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
    options =
      organization_id
      |> PointCatalog.list_points(mission_id)
      |> Enum.map(&option/1)

    query = String.trim(query)

    matches =
      options
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

  defp option(%{source: :derived} = point) do
    %ReferenceOption{
      value: point.point_id,
      label: point.qualified_name || point.point_id,
      description: describe(["Derived telemetry", point.unit && "Unit: #{point.unit}"])
    }
  end

  defp option(point) do
    %ReferenceOption{
      value: point.point_id,
      label: point.point_id,
      description:
        describe(["Active telemetry", point.description, point.unit && "Unit: #{point.unit}"])
    }
  end

  defp describe(parts), do: parts |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

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
