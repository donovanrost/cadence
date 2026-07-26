defmodule Cadence.Reads.ApplicationSurfaces.ReferenceProviders.TelemetryCatalogRevisions do
  @moduledoc "Telemetry-bearing catalog revisions available to a spacecraft application."

  @behaviour Cadence.Reads.ApplicationSurfaces.ReferenceProvider

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Extensions.Presentation.{ReferenceDefinition, ReferenceOption, ReferencePage}

  @provider_id "cadence.catalog.telemetry_revisions"

  @impl true
  def search(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :spacecraft, mission_id: mission_id},
        %ReferenceDefinition{provider_id: @provider_id, version: 1},
        query,
        limit
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(query) and
             is_integer(limit) and limit > 0 do
    query = String.trim(query)

    matches =
      organization_id
      |> Catalog.list_revisions(mission_id)
      |> Enum.filter(&(&1.telemetry_snapshot_id != nil))
      |> Enum.map(&option/1)
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

  defp option(revision) do
    %ReferenceOption{
      value: revision.catalog_revision_id,
      label: "#{revision.revision_label} (##{revision.revision_number})",
      description: "Telemetry catalog revision"
    }
  end

  defp matches?(_option, ""), do: true

  defp matches?(option, query) do
    normalized_query = String.downcase(query)

    [option.value, option.label, option.description]
    |> Enum.any?(fn candidate ->
      candidate
      |> String.downcase()
      |> String.contains?(normalized_query)
    end)
  end
end
