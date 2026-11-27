defmodule Cadence.GroundNetworks.ElementSets do
  @moduledoc """
  Each spacecraft's orbit as SGP4 mean elements (#889, slice 1 of #732; DECISIONS #114).

  An element set arrives as a TLE or an OMM, is parsed and validated, and is stored as an
  immutable row with its raw text. History is kept: a spacecraft's current element set is the one
  with the newest epoch, so a set with an older epoch is stored but doesn't replace it. The natural
  key `(mission, spacecraft, epoch, content_sha256)` makes a re-send idempotent: it answers
  `:unchanged` with the stored row.

  `submit/4` takes one to 1,000 items for one mission. It loads the named spacecraft and the
  already-stored keys in bounded batches (never a query per spacecraft) and inserts the new rows
  in one transaction. Each item is answered on its own: one bad set doesn't refuse the others.
  """

  import Ecto.Query

  alias Cadence.GroundNetworks.ElementSet
  alias Cadence.GroundNetworks.ElementSets.{Elements, ElementSetRow, HistoryCursor, Omm, Tle}
  alias Cadence.Ids
  alias Cadence.Persistence.BulkInsert
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @max_batch 1_000
  @default_history_limit 50
  @max_history_limit 200

  @type input :: {:tle, binary()} | {:omm, map() | binary()}
  @type item :: %{spacecraft_id: binary(), input: input()}
  @type result ::
          {:created, ElementSet.t()}
          | {:unchanged, ElementSet.t()}
          | {:refused, atom(), map()}

  @doc "The most items `submit/4` takes in one call."
  @spec max_batch() :: pos_integer()
  def max_batch, do: @max_batch

  @doc "Parses and validates one element set without storing it."
  @spec parse(input(), DateTime.t()) :: {:ok, Elements.t()} | Elements.refusal()
  def parse({:tle, text}, now),
    do: with({:ok, e} <- Tle.parse(text), do: Elements.validate(e, now))

  def parse({:omm, omm}, now), do: with({:ok, e} <- Omm.parse(omm), do: Elements.validate(e, now))

  @doc """
  Stores each item's element set, answering each in order. `opts`: `:actor` (the stored actor
  document, required), `:source` (`"manual"` or `"api"`, required) and `:now` (for tests).
  """
  @spec submit(binary(), binary(), [item()], keyword()) ::
          {:ok, [result()]} | {:error, :batch_too_large | :empty_batch}
  def submit(_organization_id, _mission_id, [], _opts), do: {:error, :empty_batch}

  def submit(_organization_id, _mission_id, items, _opts) when length(items) > @max_batch,
    do: {:error, :batch_too_large}

  def submit(organization_id, mission_id, items, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(items) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    context = %{
      organization_id: organization_id,
      mission_id: mission_id,
      source: Keyword.fetch!(opts, :source),
      created_by: Keyword.fetch!(opts, :actor),
      received_at: now
    }

    parsed = Enum.map(items, &parse_item(&1, now))

    Repo.transaction(fn ->
      case known_spacecraft(organization_id, mission_id, parsed) do
        {:ok, known} -> parsed |> Enum.map(&check_spacecraft(&1, known)) |> store(context)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "The spacecraft's current element set (the newest epoch), or nil when it has none."
  @spec current(binary(), binary(), binary()) :: ElementSet.t() | nil
  def current(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> history_query(mission_id, spacecraft_id)
    |> limit(1)
    |> Repo.one()
    |> then(&(&1 && ElementSetRow.to_domain(&1)))
  end

  @doc """
  One page of the spacecraft's element-set history, newest epoch first. `cursor` is the
  `next_cursor` of the page before (nil for the first); `limit` is 1–200 (default 50).
  """
  @spec history(binary(), binary(), binary(), binary() | nil, pos_integer() | nil) ::
          {:ok, %{items: [ElementSet.t()], next_cursor: binary() | nil}}
          | {:error, :invalid_cursor}
  def history(organization_id, mission_id, spacecraft_id, cursor, limit) do
    limit = clamp(limit)

    with {:ok, key} <- HistoryCursor.decode(cursor) do
      rows =
        organization_id
        |> history_query(mission_id, spacecraft_id)
        |> HistoryCursor.after_key(key)
        |> limit(^(limit + 1))
        |> Repo.all()

      {page, rest} = Enum.split(rows, limit)
      next = if rest == [], do: nil, else: HistoryCursor.encode(List.last(page))
      {:ok, %{items: Enum.map(page, &ElementSetRow.to_domain/1), next_cursor: next}}
    end
  end

  defp clamp(nil), do: @default_history_limit
  defp clamp(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_history_limit)

  defp history_query(organization_id, mission_id, spacecraft_id) do
    from(row in ElementSetRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.spacecraft_id == ^spacecraft_id,
      order_by: [desc: row.epoch, desc: row.element_set_id]
    )
  end

  defp parse_item(%{spacecraft_id: spacecraft_id, input: input}, now) do
    case parse(input, now) do
      {:ok, elements} -> {:parsed, spacecraft_id, elements}
      {:error, {reason, details}} -> {:refused, reason, details}
    end
  end

  defp known_spacecraft(organization_id, mission_id, parsed) do
    ids = for {:parsed, spacecraft_id, _elements} <- parsed, uniq: true, do: spacecraft_id

    with {:ok, found} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids),
         do: {:ok, MapSet.new(Map.keys(found))}
  end

  defp check_spacecraft({:parsed, spacecraft_id, _elements} = item, known) do
    if MapSet.member?(known, spacecraft_id),
      do: item,
      else: {:refused, :spacecraft_not_found, %{spacecraft_id: spacecraft_id}}
  end

  defp check_spacecraft(refused, _known), do: refused

  defp store(items, context) do
    keyed =
      Enum.map(items, fn
        {:parsed, spacecraft_id, elements} ->
          {:parsed, key(spacecraft_id, elements.epoch, Elements.content_sha256(elements)),
           spacecraft_id, elements}

        refused ->
          refused
      end)

    stored = stored_rows(context, keyed)
    {fresh, results} = plan(keyed, stored, context)
    inserted = insert(Enum.reverse(fresh), context)

    Enum.map(results, fn
      {:create, key} -> key |> resolve(inserted, :created) |> domain()
      {:repeat, key} -> key |> resolve(inserted, :unchanged) |> domain()
      {:unchanged, row} -> {:unchanged, ElementSetRow.to_domain(row)}
      refused -> refused
    end)
  end

  # Stored rows for these keys: one query for a whole batch (at most 1,000 keys).
  defp stored_rows(context, keyed) do
    keys = for {:parsed, key, _spacecraft_id, _elements} <- keyed, uniq: true, do: key
    fetch_keys(context, keys)
  end

  defp fetch_keys(_context, []), do: %{}

  defp fetch_keys(context, keys) do
    keys
    |> Enum.chunk_every(@max_batch)
    |> Enum.flat_map(fn chunk ->
      spacecraft_ids =
        Enum.uniq(Enum.map(chunk, fn {spacecraft_id, _epoch, _sha} -> spacecraft_id end))

      hashes = Enum.uniq(Enum.map(chunk, fn {_spacecraft_id, _epoch, sha} -> sha end))

      Repo.all(
        from(row in ElementSetRow,
          where:
            row.organization_id == ^context.organization_id and
              row.mission_id == ^context.mission_id and row.spacecraft_id in ^spacecraft_ids and
              row.content_sha256 in ^hashes
        )
      )
    end)
    |> Map.new(&{key(&1.spacecraft_id, &1.epoch, &1.content_sha256), &1})
  end

  # Each parsed item either repeats a stored row, repeats an item earlier in this request, or is
  # new. New rows get their ids here, in input order.
  defp plan(keyed, stored, context) do
    {fresh, _seen, results} =
      Enum.reduce(keyed, {[], MapSet.new(), []}, fn
        {:parsed, key, spacecraft_id, elements}, {fresh, seen, results} ->
          cond do
            row = Map.get(stored, key) ->
              {fresh, seen, [{:unchanged, row} | results]}

            MapSet.member?(seen, key) ->
              {fresh, seen, [{:repeat, key} | results]}

            true ->
              row = new_changeset(elements, spacecraft_id, context)
              {[{key, row} | fresh], MapSet.put(seen, key), [{:create, key} | results]}
          end

        refused, {fresh, seen, results} ->
          {fresh, seen, [refused | results]}
      end)

    {fresh, Enum.reverse(results)}
  end

  defp new_changeset(elements, spacecraft_id, context) do
    ElementSetRow.changeset(
      elements,
      Map.merge(context, %{element_set_id: Ids.new("elset"), spacecraft_id: spacecraft_id})
    )
  end

  # A concurrent request may store the same key first; its row then answers for ours.
  defp insert([], _context), do: %{}

  defp insert(fresh, context) do
    changesets = Enum.map(fresh, fn {_key, changeset} -> changeset end)

    {:ok, count} =
      BulkInsert.changesets(ElementSetRow, changesets,
        on_conflict: :nothing,
        conflict_target: [:mission_id, :spacecraft_id, :epoch, :content_sha256]
      )

    rows =
      Map.new(fresh, fn {key, changeset} ->
        {key, Ecto.Changeset.apply_action!(changeset, :insert)}
      end)

    if count == length(fresh),
      do: Map.new(rows, fn {key, row} -> {key, {:created, row}} end),
      else: winners(rows, fetch_keys(context, Map.keys(rows)))
  end

  defp winners(rows, stored) do
    Map.new(rows, fn {key, row} ->
      winner = Map.fetch!(stored, key)
      status = if winner.element_set_id == row.element_set_id, do: :created, else: :unchanged
      {key, {status, winner}}
    end)
  end

  defp resolve(key, inserted, :created), do: Map.fetch!(inserted, key)

  defp resolve(key, inserted, :unchanged) do
    {_status, row} = Map.fetch!(inserted, key)
    {:unchanged, row}
  end

  defp domain({status, row}), do: {status, ElementSetRow.to_domain(row)}

  defp key(spacecraft_id, %DateTime{} = epoch, sha),
    do: {spacecraft_id, DateTime.to_unix(epoch, :microsecond), sha}
end
