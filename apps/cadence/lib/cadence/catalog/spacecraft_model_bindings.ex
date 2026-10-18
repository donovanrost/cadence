defmodule Cadence.Catalog.SpacecraftModelBindings do
  @moduledoc "Finite immutable per-spacecraft model evidence; contains no persistence or activation operations."
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  def entries(%{"spacecraft_configurations" => entries, "spacecraft_configuration_version" => 1})
      when is_map(entries) and map_size(entries) in 1..100 do
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
