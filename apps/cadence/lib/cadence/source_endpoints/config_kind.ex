defmodule Cadence.SourceEndpoints.ConfigKind do
  @moduledoc "Reviews and applies relay declarations on existing source endpoints."

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Platform.ConfigFields, as: Fields
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @kind "source_endpoint"
  @relay_fields ~w(relay display_name spacecraft_id)
  @origin_path "relay.origin_spacecraft_ids"

  @impl true
  def kind, do: @kind

  @impl true
  def id_prefix, do: @kind

  @impl true
  def translate(_organization_id, _mission_id, _previous, proposed, touched) do
    errors =
      for path <- touched,
          path not in ["relay", @origin_path],
          do: Fields.error(path, "Only the relay declaration can be changed here.")

    Fields.result(proposed, errors)
  end

  @impl true
  def load(organization_id, mission_id, ids) do
    organization_id
    |> SourceEndpoints.fetch_source_endpoints_by_ids(mission_id, ids)
    |> Map.new(fn {id, endpoint} -> {id, document(endpoint)} end)
  end

  @impl true
  def normalize(:update, _id, %{} = document) do
    with {:ok, relay} <- normalize_relay(document["relay"], document["spacecraft_id"]) do
      Fields.result(Map.put(document, "relay", relay), Fields.only(document, @relay_fields))
    end
  end

  def normalize(_action, _id, _document) do
    {:error, [Fields.error("relay", "Update the relay on an existing source endpoint.")]}
  end

  defp normalize_relay(nil, _endpoint_craft), do: {:ok, nil}

  defp normalize_relay(%{"origin_spacecraft_ids" => ids} = relay, endpoint_craft)
       when is_list(ids) and map_size(relay) == 1 do
    if Enum.all?(ids, &spacecraft_id?/1) do
      ids = ids |> Enum.reject(&(&1 == endpoint_craft)) |> Enum.uniq() |> Enum.sort()
      {:ok, %{"origin_spacecraft_ids" => ids}}
    else
      invalid_relay()
    end
  end

  defp normalize_relay(_value, _endpoint_craft), do: invalid_relay()

  defp spacecraft_id?(id), do: is_binary(id) and id != "" and String.trim(id) == id

  defp invalid_relay do
    {:error, [Fields.error(@origin_path, "Enter a list of spacecraft IDs.")]}
  end

  @impl true
  def validate(_organization_id, _mission_id, :update, _id, previous, proposed) do
    errors =
      for field <- ~w(display_name spacecraft_id),
          Map.get(previous, field) != Map.get(proposed, field),
          do: Fields.error(field, "Only the relay declaration can be changed here.")

    errors_result(errors)
  end

  # Validate the final origin sets once, before the transaction commits. A later spacecraft
  # op in the same set can change a SCID, and several relays can name the same spacecraft.
  @impl true
  def finalize(organization_id, mission_id, entries) do
    changed = for %{kind: @kind, proposed: proposed} <- entries, do: proposed

    with :ok <- validate_origin_sets(organization_id, mission_id, changed) do
      {:ok, [], []}
    end
  end

  defp validate_origin_sets(organization_id, mission_id, documents) do
    sets =
      for %{"relay" => %{"origin_spacecraft_ids" => ids}} = doc <- documents,
          do: origins(doc, ids)

    all_ids = sets |> Enum.flat_map(& &1) |> Enum.uniq()

    with {:ok, crafts} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, all_ids) do
      sets |> Enum.flat_map(&origin_errors(&1, crafts)) |> errors_result()
    end
  end

  defp origins(%{"spacecraft_id" => craft}, ids) when is_binary(craft) and craft != "",
    do: Enum.uniq([craft | ids])

  defp origins(_document, ids), do: ids

  defp origin_errors(ids, crafts) do
    scoped = Map.take(crafts, ids)

    cond do
      map_size(scoped) != length(ids) ->
        [
          origin_error(
            :relay_origin_not_in_mission,
            "Every relay spacecraft must belong to this mission."
          )
        ]

      Enum.any?(scoped, fn {_id, spacecraft} -> is_nil(spacecraft.scid) end) ->
        [origin_error(:relay_origin_without_scid, "Every relay spacecraft must have a SCID.")]

      true ->
        []
    end
  end

  defp origin_error(code, message), do: Map.put(Fields.error(@origin_path, message), :code, code)
  defp errors_result([]), do: :ok
  defp errors_result(errors), do: {:error, errors}

  @impl true
  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    relay = enabled_relay(proposed["relay"])

    with {:ok, endpoint} <-
           SourceEndpoints.write_relay(organization_id, mission_id, id, relay) do
      {:ok, document(endpoint), []}
    end
  end

  @impl true
  def summary(:update, _previous, proposed) do
    if enabled_relay(proposed["relay"]),
      do: "Change relay origin spacecraft",
      else: "Remove relay declaration"
  end

  defp enabled_relay(%{"origin_spacecraft_ids" => [_ | _]} = relay), do: relay
  defp enabled_relay(_relay), do: nil

  @impl true
  def runtime_impact(:update, _previous, _proposed), do: :generation

  defp document(endpoint) do
    %{
      "display_name" => endpoint.display_name || endpoint.source_ref,
      "spacecraft_id" => endpoint.spacecraft_id,
      "relay" => endpoint.relay
    }
  end
end
