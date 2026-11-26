defmodule Cadence.Catalog.SpacecraftModelBindings do
  @moduledoc "Finite immutable per-spacecraft model evidence; contains no persistence or activation operations."
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  @doc "Validates a fleet of entries (`spacecraft_id => entry`). A fleet has no size cap."
  def validate(entries) when is_map(entries) and map_size(entries) > 0 do
    if Enum.all?(entries, &valid_entry?/1) and unique_endpoints?(entries),
      do: {:ok, entries},
      else: {:error, :invalid_spacecraft_model_bindings}
  end

  def validate(_entries), do: {:error, :invalid_spacecraft_model_bindings}

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
    length(ids) == length(Enum.uniq(ids))
  end
end
