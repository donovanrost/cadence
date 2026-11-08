defmodule Cadence.Runtime.PartitionMetadata do
  @moduledoc """
  Projects fleet admission evidence to the selected source.

  Arbitrary existing capability metadata is preserved. Known fleet configuration
  and review collections retain only this source's spacecraft. The complete
  immutable evidence remains on the mission specification for audit and export.
  """
  alias Cadence.Runtime.PartitionKey

  def project(
        %{"spacecraft_configurations" => configurations} = metadata,
        %PartitionKey{affinity: :source_endpoint, value: source}
      )
      when is_map(configurations) do
    selected =
      Map.filter(configurations, fn {_id, entry} ->
        source in Map.get(entry, "source_endpoint_ids", [])
      end)

    metadata
    |> Map.put("spacecraft_configurations", selected)
    |> project_review(Map.keys(selected))
  end

  def project(metadata, _partition), do: metadata

  defp project_review(
         %{"configuration_review" => %{"spacecraft_reviews" => reviews} = review} = metadata,
         ids
       ) do
    Map.put(metadata, "configuration_review", %{
      review
      | "spacecraft_reviews" => Map.take(reviews, ids)
    })
  end

  defp project_review(%{"configuration_review" => %{"spacecraft_id" => id}} = metadata, ids) do
    if id in ids, do: metadata, else: Map.delete(metadata, "configuration_review")
  end

  defp project_review(metadata, _ids), do: metadata
end
