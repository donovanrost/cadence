defmodule Cadence.Catalog.FleetSnapshot do
  @moduledoc """
  The per-spacecraft configuration entries an activation admits ("the fleet"), with one read
  API over both metadata versions (`docs/apogee/domain/fleet-snapshot.md`).

  - **v1** (legacy): entries inline in `metadata["spacecraft_configurations"]`.
  - **v2**: metadata carries only `"fleet" => %{"mission_id", "sha256", "count"}`. Entries live in
    content-addressed tables: an unchanged spacecraft re-uses its entry row, an identical fleet
    re-uses its fleet row, and nothing is copied into activation rows, active rows or events.

  Entries are validated once, by `store/2`. Readers ask for what they need (one spacecraft, one
  source endpoint, the commanding groups) instead of decoding the whole fleet. v1 rows stay
  readable; a mission moves to v2 on its next activation.
  """

  import Ecto.Query

  alias Cadence.Catalog.FleetSnapshot.{EntryRow, FleetRow, MemberRow}
  alias Cadence.Catalog.SpacecraftModelBindings
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo

  @version 2
  @chunk 1_000

  @type fleet :: %{required(String.t()) => term()}

  @doc "Metadata v2 for a stored fleet and its review evidence."
  @spec metadata(fleet(), map()) :: map()
  def metadata(fleet, review) do
    %{
      "spacecraft_configuration_version" => @version,
      "fleet" => fleet,
      "configuration_review" => review
    }
  end

  @doc """
  Validates and stores a fleet (`spacecraft_id => entry`). Idempotent: storing the same fleet
  again returns the same reference.
  """
  @spec store(String.t(), map()) :: {:ok, fleet()} | {:error, term()}
  def store(mission_id, entries) when is_binary(mission_id) and is_map(entries) do
    entries = Map.new(entries, fn {id, entry} -> {id, JsonDocument.encode(entry)} end)

    with {:ok, entries} <- SpacecraftModelBindings.validate(entries) do
      hashed =
        Map.new(entries, fn {id, entry} -> {id, {ContentHash.term_sha256(entry), entry}} end)

      fleet_sha =
        hashed
        |> Enum.map(fn {id, {sha, _}} -> {id, sha} end)
        |> Enum.sort()
        |> ContentHash.term_sha256()

      Repo.transaction(fn -> persist(mission_id, fleet_sha, hashed) end)
      |> case do
        {:ok, :ok} ->
          {:ok,
           %{"mission_id" => mission_id, "sha256" => fleet_sha, "count" => map_size(entries)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Whether the metadata carries a fleet (either version)."
  @spec fleet?(map()) :: boolean()
  def fleet?(%{"spacecraft_configuration_version" => 2, "fleet" => %{}}), do: true

  def fleet?(%{"spacecraft_configuration_version" => 1, "spacecraft_configurations" => _}),
    do: true

  def fleet?(_metadata), do: false

  @doc "Stable identity of the fleet, for equality checks."
  @spec fleet_sha256(map()) :: String.t() | nil
  def fleet_sha256(%{"spacecraft_configuration_version" => 2, "fleet" => %{"sha256" => sha}}),
    do: sha

  def fleet_sha256(%{"spacecraft_configuration_version" => 1} = metadata) do
    case SpacecraftModelBindings.entries(metadata) do
      {:ok, entries} -> entries |> JsonDocument.encode() |> ContentHash.term_sha256()
      {:error, _} -> nil
    end
  end

  def fleet_sha256(_metadata), do: nil

  @doc "Every entry of the fleet (`spacecraft_id => entry`)."
  @spec entries(map()) :: {:ok, map()} | {:error, :invalid_spacecraft_model_bindings}
  def entries(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}) do
    case members_query(fleet) do
      nil -> {:error, :invalid_spacecraft_model_bindings}
      query -> query |> with_entries() |> Repo.all() |> Map.new() |> counted(fleet)
    end
  end

  def entries(metadata), do: SpacecraftModelBindings.entries(metadata)

  @doc "One spacecraft's entry."
  @spec entry(map(), String.t()) :: {:ok, map()} | {:error, :spacecraft_model_not_active}
  def entry(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}, spacecraft_id) do
    fleet
    |> members_query()
    |> one_entry(&where(&1, [m], m.spacecraft_id == ^spacecraft_id))
  end

  def entry(metadata, spacecraft_id) do
    with {:ok, entries} <- SpacecraftModelBindings.entries(metadata),
         %{} = entry <- entries[spacecraft_id] do
      {:ok, entry}
    else
      _ -> {:error, :spacecraft_model_not_active}
    end
  end

  @doc "The entry of the spacecraft that owns a source endpoint."
  @spec entry_for_source(map(), String.t()) ::
          {:ok, map()} | {:error, :spacecraft_model_not_active}
  def entry_for_source(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}, source_id)
      when is_binary(source_id) do
    fleet
    |> members_query()
    |> one_entry(&where(&1, [m], fragment("? = ANY(?)", ^source_id, m.source_endpoint_ids)))
  end

  def entry_for_source(metadata, source_id),
    do: SpacecraftModelBindings.entry_for_source(metadata, source_id)

  @doc "Spacecraft ids in the fleet, sorted."
  @spec spacecraft_ids(map()) :: [String.t()]
  def spacecraft_ids(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}) do
    case members_query(fleet) do
      nil ->
        []

      query ->
        # Sorted in Elixir (bytewise), whatever the database's text collation (#56).
        query |> select([m], m.spacecraft_id) |> Repo.all() |> Enum.sort()
    end
  end

  def spacecraft_ids(metadata) do
    case SpacecraftModelBindings.entries(metadata) do
      {:ok, entries} -> entries |> Map.keys() |> Enum.sort()
      {:error, _} -> []
    end
  end

  @doc "`spacecraft_id => catalog_revision_id` without loading entries."
  @spec catalog_usage(map()) :: %{String.t() => String.t()}
  def catalog_usage(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}) do
    case members_query(fleet) do
      nil ->
        %{}

      query ->
        query |> select([m], {m.spacecraft_id, m.catalog_revision_id}) |> Repo.all() |> Map.new()
    end
  end

  def catalog_usage(metadata) do
    case SpacecraftModelBindings.entries(metadata) do
      {:ok, entries} -> Map.new(entries, fn {id, entry} -> {id, entry["catalog_revision_id"]} end)
      {:error, _} -> %{}
    end
  end

  @doc "Commanding-enabled entries only (`spacecraft_id => entry`)."
  @spec commanding_entries(map()) :: {:ok, map()} | {:error, term()}
  def commanding_entries(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}) do
    case members_query(fleet) do
      nil ->
        {:error, :invalid_spacecraft_model_bindings}

      query ->
        {:ok,
         query |> where([m], m.commanding_enabled) |> with_entries() |> Repo.all() |> Map.new()}
    end
  end

  def commanding_entries(metadata) do
    with {:ok, entries} <- SpacecraftModelBindings.entries(metadata),
         do: {:ok, Map.filter(entries, fn {_id, entry} -> entry["commanding_enabled"] end)}
  end

  defp persist(mission_id, fleet_sha, hashed) do
    now = DateTime.utc_now()

    if Repo.exists?(
         where(FleetRow, [f], f.mission_id == ^mission_id and f.fleet_sha256 == ^fleet_sha)
       ) do
      :ok
    else
      hashed
      |> Enum.map(fn {_id, {sha, entry}} ->
        %{mission_id: mission_id, entry_sha256: sha, entry: entry, inserted_at: now}
      end)
      |> Enum.uniq_by(& &1.entry_sha256)
      |> Enum.chunk_every(@chunk)
      |> Enum.each(&Repo.insert_all(EntryRow, &1, on_conflict: :nothing))

      hashed
      |> Enum.map(fn {id, {sha, entry}} -> member(mission_id, fleet_sha, id, sha, entry) end)
      |> Enum.chunk_every(@chunk)
      |> Enum.each(&Repo.insert_all(MemberRow, &1, on_conflict: :nothing))

      Repo.insert_all(
        FleetRow,
        [
          %{
            mission_id: mission_id,
            fleet_sha256: fleet_sha,
            spacecraft_count: map_size(hashed),
            inserted_at: now
          }
        ],
        on_conflict: :nothing
      )

      :ok
    end
  end

  defp member(mission_id, fleet_sha, spacecraft_id, entry_sha, entry) do
    %{
      mission_id: mission_id,
      fleet_sha256: fleet_sha,
      spacecraft_id: spacecraft_id,
      entry_sha256: entry_sha,
      source_endpoint_ids: entry["source_endpoint_ids"],
      commanding_enabled: entry["commanding_enabled"],
      catalog_revision_id: entry["catalog_revision_id"],
      mission_model_sha256: ContentHash.term_sha256(entry["mission_model"])
    }
  end

  defp members_query(%{"mission_id" => mission_id, "sha256" => sha})
       when is_binary(mission_id) and is_binary(sha),
       do: where(MemberRow, [m], m.mission_id == ^mission_id and m.fleet_sha256 == ^sha)

  defp members_query(_fleet), do: nil

  defp with_entries(query) do
    query
    |> join(:inner, [m], e in EntryRow,
      on: e.mission_id == m.mission_id and e.entry_sha256 == m.entry_sha256
    )
    |> select([m, e], {m.spacecraft_id, e.entry})
  end

  defp one_entry(nil, _filter), do: {:error, :spacecraft_model_not_active}

  defp one_entry(query, filter) do
    query
    |> filter.()
    |> with_entries()
    |> limit(1)
    |> Repo.one()
    |> case do
      {_id, entry} -> {:ok, entry}
      nil -> {:error, :spacecraft_model_not_active}
    end
  end

  defp counted(entries, %{"count" => count}) when map_size(entries) == count, do: {:ok, entries}
  defp counted(_entries, _fleet), do: {:error, :invalid_spacecraft_model_bindings}
end
