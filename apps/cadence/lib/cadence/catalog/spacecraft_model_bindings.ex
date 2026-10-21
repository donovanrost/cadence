defmodule Cadence.Catalog.SpacecraftModelBindings do
  @moduledoc "Finite immutable per-spacecraft model evidence; contains no persistence or activation operations."
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  @max_spacecraft 500
  @max_metadata_bytes 4_194_304

  def max_spacecraft, do: @max_spacecraft
  def max_metadata_bytes, do: @max_metadata_bytes

  def review_for(metadata, spacecraft_id) do
    case metadata["configuration_review"] do
      %{"spacecraft_id" => ^spacecraft_id} = review ->
        review

      %{"spacecraft_reviews" => reviews, "base_activation_id" => base} when is_map(reviews) ->
        case reviews[spacecraft_id] do
          %{} = review -> Map.put(review, "base_activation_id", base)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def reviewed_spacecraft_ids(metadata) do
    case metadata["configuration_review"] do
      %{"spacecraft_id" => id} when is_binary(id) ->
        {:ok, [id]}

      %{"spacecraft_reviews" => reviews}
      when is_map(reviews) and map_size(reviews) in 1..@max_spacecraft ->
        if Enum.all?(Map.keys(reviews), &is_binary/1),
          do: {:ok, Enum.sort(Map.keys(reviews))},
          else: {:error, :spacecraft_configuration_review_stale}

      _ ->
        {:error, :spacecraft_configuration_review_stale}
    end
  end

  def entries(%{"spacecraft_configurations" => entries, "spacecraft_configuration_version" => 1})
      when is_map(entries) and map_size(entries) in 1..@max_spacecraft do
    if Enum.all?(entries, &valid_entry?/1) and unique_endpoints?(entries),
      do: {:ok, entries},
      else: {:error, :invalid_spacecraft_model_bindings}
  end

  def entries(_), do: {:error, :invalid_spacecraft_model_bindings}

  def entry_for_source(metadata, source_endpoint_id) when is_binary(source_endpoint_id) do
    with {:ok, entries} <- entries(metadata) do
      case Enum.find(entries, &source_entry?(&1, source_endpoint_id)) do
        {_id, entry} -> {:ok, entry}
        nil -> {:error, :spacecraft_model_not_active}
      end
    end
  end

  def entry_for_source(_, _), do: {:error, :spacecraft_model_not_active}

  defp source_entry?({_id, entry}, source), do: source in entry["source_endpoint_ids"]

  defp valid_entry?({id, entry}) when is_binary(id) and is_map(entry) do
    byte_size(id) in 1..255 and is_binary(entry["catalog_revision_id"]) and
      valid_document?(entry) and is_map(entry["mission_model"]) and
      is_boolean(entry["commanding_enabled"]) and
      endpoints?(entry["source_endpoint_ids"])
  end

  defp valid_entry?(_), do: false

  defp valid_document?(entry) do
    case ConfigurationInput.decode(entry["document"]) do
      {:ok, document} ->
        document["catalog_revision_id"] == entry["catalog_revision_id"] and
          document["commanding_enabled"] == entry["commanding_enabled"]

      _ ->
        false
    end
  end

  defp endpoints?(ids) when is_list(ids) and length(ids) in 1..100,
    do: Enum.all?(ids, &(is_binary(&1) and byte_size(&1) in 1..255))

  defp endpoints?(_), do: false

  defp unique_endpoints?(entries) do
    ids = Enum.flat_map(entries, fn {_id, entry} -> entry["source_endpoint_ids"] end)
    length(ids) <= 1000 and length(ids) == length(Enum.uniq(ids))
  end
end
