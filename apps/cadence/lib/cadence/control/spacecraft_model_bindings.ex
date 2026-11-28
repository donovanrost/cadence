defmodule Cadence.Control.SpacecraftModelBindings do
  @moduledoc "Admits the exact model assigned to each spacecraft in an activation generation."

  alias Cadence.Catalog
  alias Cadence.Catalog.CompositionPins
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Compositions
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  def validate(organization_id, mission_id, metadata) do
    with {:ok, entries} <- FleetSnapshot.entries(metadata),
         :ok <- validate_entries(organization_id, mission_id, entries) do
      validate_models(organization_id, mission_id, entries)
    end
  end

  # Each entry's spacecraft exists, its catalog is the model's (or a linked composition's), and its
  # source endpoints are its own. The spacecraft and endpoints are read once for the whole fleet and
  # each distinct catalog once, so an approval of a large review runs a number of queries that does
  # not grow per spacecraft (#1020); the checks and their order per entry are unchanged.
  defp validate_entries(organization_id, mission_id, entries) do
    ids = entries |> Map.keys() |> Enum.sort()

    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids) do
      endpoints =
        SourceEndpoints.list_source_endpoints_for_spacecrafts(organization_id, mission_id, ids)

      context = %{spacecraft: spacecraft, endpoints: endpoints}
      each_entry(ids, entries, {organization_id, mission_id}, context)
    end
  end

  defp each_entry(ids, entries, scope, context) do
    Enum.reduce_while(ids, {:ok, %{}}, fn id, {:ok, memo} ->
      case validate_entry(scope, id, entries[id], context, memo) do
        {:ok, memo} -> {:cont, {:ok, memo}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _memo} -> :ok
      error -> error
    end
  end

  defp validate_models(organization_id, mission_id, entries) do
    entries
    |> Enum.map(fn {_id, entry} -> entry["mission_model"] end)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn manifest, :ok ->
      case MissionModelPromotion.runtime_basis(organization_id, mission_id, manifest) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_entry({organization_id, mission_id}, spacecraft_id, entry, context, memo) do
    catalog_id = entry["catalog_revision_id"]
    model_id = entry["mission_model"]["revision_id"]

    with :ok <- spacecraft_exists(context.spacecraft, spacecraft_id),
         {:ok, catalog, memo} <- catalog(organization_id, mission_id, catalog_id, memo),
         {:ok, true, memo} <- catalog_model(organization_id, mission_id, catalog, model_id, memo),
         :ok <- validate_endpoints(context.endpoints, spacecraft_id, entry) do
      {:ok, memo}
    else
      {:ok, false, _memo} -> {:error, :spacecraft_catalog_model_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp spacecraft_exists(spacecraft, id),
    do: if(is_map_key(spacecraft, id), do: :ok, else: {:error, :spacecraft_not_found})

  defp catalog(organization_id, mission_id, catalog_id, memo) do
    case memo do
      %{{:catalog, ^catalog_id} => catalog} ->
        {:ok, catalog, memo}

      _ ->
        with {:ok, catalog} <- Catalog.fetch_revision(organization_id, mission_id, catalog_id),
             do: {:ok, catalog, Map.put(memo, {:catalog, catalog_id}, catalog)}
    end
  end

  # Each distinct (catalog, model revision) pair is decided once.
  defp catalog_model(organization_id, mission_id, catalog, model_id, memo) do
    key = {:model, catalog.catalog_revision_id, model_id}

    case memo do
      %{^key => answer} ->
        {:ok, answer, memo}

      _ ->
        answer = catalog_model?(organization_id, mission_id, catalog, model_id)
        {:ok, answer, Map.put(memo, key, answer)}
    end
  end

  # The catalog's own model revision, or (D3, #544) a revision its one-layer composition links:
  # after a compiler version bump the craft runs the selected approved compile, not the catalog's
  # newest. A revision of another composition is still a mismatch.
  defp catalog_model?(_organization_id, _mission_id, %{mission_model_revision_id: id}, id),
    do: true

  defp catalog_model?(organization_id, mission_id, catalog, revision_id)
       when is_binary(revision_id) do
    with {:ok, composition} <-
           CompositionPins.for_catalog_revision(
             organization_id,
             mission_id,
             catalog.catalog_revision_id
           ),
         {:ok, %{composition_id: ^composition}} <-
           Compositions.for_revision(organization_id, mission_id, revision_id) do
      true
    else
      _other -> false
    end
  end

  defp catalog_model?(_organization_id, _mission_id, _catalog, _revision_id), do: false

  def runtime_basis(activation) do
    with {:ok, entries} <- FleetSnapshot.entries(activation.metadata),
         {:ok, bases} <- resolve_entries(activation, entries) do
      # The complete source map is part of the receiver's runtime identity. A
      # partition must select its own entry before executing any model plan.
      [{_endpoint, first} | _] = Enum.sort(bases)
      {:ok, Map.put(first, :source_runtime_bases, bases)}
    end
  end

  def runtime_basis(activation, source_endpoint_id) do
    with {:ok, entry} <- FleetSnapshot.entry_for_source(activation.metadata, source_endpoint_id) do
      MissionModelPromotion.runtime_basis(%{activation | metadata: entry})
    end
  end

  def command_basis(activation, source_endpoint_id) do
    with {:ok, entry} <- command_entry(activation.metadata, source_endpoint_id),
         true <- entry["commanding_enabled"] do
      MissionModels.command_authoring_basis(
        activation.organization_id,
        activation.mission_id,
        entry["mission_model"]
      )
    else
      false -> {:error, :spacecraft_commanding_not_active}
      {:error, reason} -> {:error, reason}
    end
  end

  defp commanding_entry?({_id, entry}), do: entry["commanding_enabled"]

  defp command_entry(metadata, nil) do
    with {:ok, entries} <- FleetSnapshot.commanding_entries(metadata) do
      case entries
           |> Enum.sort()
           |> Enum.find(&commanding_entry?/1) do
        {_id, entry} -> {:ok, entry}
        nil -> {:error, :spacecraft_commanding_not_active}
      end
    end
  end

  defp command_entry(metadata, source), do: FleetSnapshot.entry_for_source(metadata, source)

  defp resolve_entries(activation, entries) do
    entries
    |> Enum.group_by(fn {_id, entry} -> {entry["mission_model"], profile_framing(entry)} end)
    |> Enum.reduce_while({:ok, %{}}, fn {{manifest, framing}, grouped}, {:ok, bases} ->
      case MissionModelPromotion.runtime_basis(%{
             activation
             | metadata: %{"mission_model" => manifest}
           }) do
        {:ok, basis} ->
          {:cont, {:ok, Map.merge(bases, source_bases(grouped, basis, framing))}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp source_bases(grouped, basis, framing) do
    basis = if framing, do: Map.put(basis, :framing, framing), else: basis

    grouped
    |> Enum.flat_map(&Map.fetch!(elem(&1, 1), "source_endpoint_ids"))
    |> Map.new(&{&1, basis})
  end

  # Only entries produced with profile framing authority (change-set generations) carry framing
  # into the runtime; legacy entries keep decoding with the transport's ingress metadata.
  defp profile_framing(%{"framing_authority" => "profile", "framing" => %{} = framing}),
    do: framing

  defp profile_framing(_entry), do: nil

  defp validate_endpoints(endpoints, spacecraft_id, entry) do
    own = endpoints |> Map.get(spacecraft_id, []) |> MapSet.new(& &1.source_endpoint_id)

    if Enum.all?(entry["source_endpoint_ids"], &MapSet.member?(own, &1)),
      do: :ok,
      else: {:error, :spacecraft_model_source_mismatch}
  end
end
