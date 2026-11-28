defmodule Cadence.Catalog.FleetSnapshot do
  @moduledoc """
  The per-spacecraft configuration entries an activation admits ("the fleet"), with one read
  API (`docs/apogee/domain/fleet-snapshot.md`).

  Metadata carries only `"fleet" => %{"mission_id", "sha256", "count"}`. Entries live in
  content-addressed tables: an unchanged spacecraft re-uses its entry row, an identical fleet
  re-uses its fleet row, and nothing is copied into activation rows, active rows or events. A
  fleet has no size cap.

  Entries are validated once, by `store/2`. Readers ask for what they need (one spacecraft, one
  source endpoint, the commanding groups) instead of decoding the whole fleet.
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

  def fleet?(_metadata), do: false

  @doc "Stable identity of the fleet, for equality checks."
  @spec fleet_sha256(map()) :: String.t() | nil
  def fleet_sha256(%{"spacecraft_configuration_version" => 2, "fleet" => %{"sha256" => sha}}),
    do: sha

  def fleet_sha256(_metadata), do: nil

  @doc """
  What commands resolve against in the fleet, as one digest (#1107): per craft, in id order, whether
  commanding is on, its configuration revision and version, its catalog revision, its source
  endpoints and its **command** runtime plan's id (content-derived). Nothing about its other plans or
  its model revision's id, so a generation that only moves craft to a new revision with the same command plan
  (a monitoring apply) leaves it equal. Computed in the database: one read, no entries decoded
  here, for a fleet of any size. `{:error, :invalid_spacecraft_model_bindings}` when `metadata`
  isn't a v2 fleet.
  """
  @spec command_digest(map()) :: {:ok, String.t()} | {:error, :invalid_spacecraft_model_bindings}
  def command_digest(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}) do
    case members_query(fleet) do
      nil ->
        {:error, :invalid_spacecraft_model_bindings}

      query ->
        digest =
          query
          |> join(:inner, [m], e in EntryRow,
            on: e.mission_id == m.mission_id and e.entry_sha256 == m.entry_sha256
          )
          |> select(
            [m, e],
            fragment(
              """
              encode(sha256(convert_to(coalesce(string_agg(? || ':' || jsonb_build_array(
                ?->'commanding_enabled', ?->'configuration_revision_id', ?->'configuration_version',
                ?->'catalog_revision_id', ?->'source_endpoint_ids', ?->'mission_model'->'plans'->'command'->'plan_id'
              )::text, '|' ORDER BY ?), ''), 'UTF8')), 'hex')
              """,
              m.spacecraft_id,
              e.entry,
              e.entry,
              e.entry,
              e.entry,
              e.entry,
              e.entry,
              m.spacecraft_id
            )
          )
          |> Repo.one()

        {:ok, digest}
    end
  end

  def command_digest(_metadata), do: {:error, :invalid_spacecraft_model_bindings}

  @doc "Every entry of the fleet (`spacecraft_id => entry`)."
  @spec entries(map()) :: {:ok, map()} | {:error, :invalid_spacecraft_model_bindings}
  def entries(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}) do
    case members_query(fleet) do
      nil -> {:error, :invalid_spacecraft_model_bindings}
      query -> query |> with_entries() |> Repo.all() |> Map.new() |> counted(fleet)
    end
  end

  def entries(_metadata), do: {:error, :invalid_spacecraft_model_bindings}

  @doc """
  The entries of `spacecraft_ids` only (`spacecraft_id => entry`; absent: not in the fleet), in
  one query for a v2 fleet, whatever the count (E2, #546).
  """
  @spec entries_for(map(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def entries_for(_metadata, []), do: {:ok, %{}}

  def entries_for(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}, spacecraft_ids) do
    case members_query(fleet) do
      nil ->
        {:error, :invalid_spacecraft_model_bindings}

      query ->
        {:ok,
         query
         |> where([m], m.spacecraft_id in ^spacecraft_ids)
         |> with_entries()
         |> Repo.all()
         |> Map.new()}
    end
  end

  def entries_for(_metadata, _spacecraft_ids), do: {:error, :invalid_spacecraft_model_bindings}

  @doc """
  The spacecraft of an activation's fleet whose entry runs `catalog_revision_id` (#678), in one
  query over the fleet's members (the column readers filter on). `[]` for a metadata that isn't
  a v2 fleet.
  """
  @spec spacecraft_on_catalog(map(), String.t()) :: [String.t()]
  def spacecraft_on_catalog(
        %{"spacecraft_configuration_version" => 2, "fleet" => fleet},
        catalog_revision_id
      )
      when is_binary(catalog_revision_id) do
    case members_query(fleet) do
      nil ->
        []

      query ->
        query
        |> where([m], m.catalog_revision_id == ^catalog_revision_id)
        |> select([m], m.spacecraft_id)
        |> Repo.all()
    end
  end

  def spacecraft_on_catalog(_metadata, _catalog_revision_id), do: []

  @doc """
  The entries that own `source_ids` (`source_id => entry`; absent: no entry owns it), in one query
  for a v2 fleet whatever the count: `entry_for_source/2` for many sources at once.
  """
  @spec entries_for_sources(map(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def entries_for_sources(_metadata, []), do: {:ok, %{}}

  def entries_for_sources(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}, ids) do
    case members_query(fleet) do
      nil ->
        {:error, :invalid_spacecraft_model_bindings}

      query ->
        wanted = MapSet.new(ids)

        {:ok,
         query
         |> where([m], fragment("? && ?", m.source_endpoint_ids, type(^ids, {:array, :string})))
         |> with_entries()
         |> Repo.all()
         |> Enum.flat_map(fn {_spacecraft_id, entry} ->
           for source <- Map.get(entry, "source_endpoint_ids", []),
               MapSet.member?(wanted, source),
               do: {source, entry}
         end)
         |> Map.new()}
    end
  end

  def entries_for_sources(_metadata, _ids), do: {:error, :spacecraft_model_not_active}

  @doc "One spacecraft's entry."
  @spec entry(map(), String.t()) :: {:ok, map()} | {:error, :spacecraft_model_not_active}
  def entry(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}, spacecraft_id) do
    fleet
    |> members_query()
    |> one_entry(&where(&1, [m], m.spacecraft_id == ^spacecraft_id))
  end

  def entry(_metadata, _spacecraft_id), do: {:error, :spacecraft_model_not_active}

  @doc "The entry of the spacecraft that owns a source endpoint."
  @spec entry_for_source(map(), String.t()) ::
          {:ok, map()} | {:error, :spacecraft_model_not_active}
  def entry_for_source(%{"spacecraft_configuration_version" => 2, "fleet" => fleet}, source_id)
      when is_binary(source_id) do
    fleet
    |> members_query()
    |> one_entry(&where(&1, [m], fragment("? = ANY(?)", ^source_id, m.source_endpoint_ids)))
  end

  def entry_for_source(_metadata, _source_id), do: {:error, :spacecraft_model_not_active}

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

  def spacecraft_ids(_metadata), do: []

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

  def catalog_usage(_metadata), do: %{}

  @doc false
  def revision_assignments_query(fleet) do
    from(member in MemberRow,
      join: fleet in subquery(fleet),
      on:
        member.organization_id == fleet.organization_id and
          member.mission_id == fleet.mission_id and member.fleet_sha256 == fleet.fleet_sha256,
      join: entry in EntryRow,
      on:
        entry.organization_id == member.organization_id and entry.mission_id == member.mission_id and
          entry.entry_sha256 == member.entry_sha256,
      select: %{
        spacecraft_id: member.spacecraft_id,
        revision_id: fragment("? #>> '{mission_model,revision_id}'", entry.entry)
      }
    )
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

  def commanding_entries(_metadata), do: {:error, :invalid_spacecraft_model_bindings}

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
