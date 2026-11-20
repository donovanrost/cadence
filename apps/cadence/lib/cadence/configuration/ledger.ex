defmodule Cadence.Configuration.Ledger do
  @moduledoc """
  The mission configuration revision ledger: the head pointer, revisions and their entries.

  A mission's ledger starts with a `baseline` revision `r1` ("configuration as of the start of the
  ledger") the first time it is touched. There are no entries before r1, so nothing can be
  compared with or rolled back past it.
  """

  import Ecto.Query

  alias Cadence.Configuration.{Document, HeadRow, RevisionEntryRow, RevisionRow}
  alias Cadence.Ids
  alias Cadence.Repo

  @baseline_summary "Configuration as of the start of the revision ledger"

  @doc "Returns the head, creating the r1 baseline if the mission has no ledger yet."
  @spec ensure_head(String.t(), String.t()) :: HeadRow.t()
  def ensure_head(organization_id, mission_id) do
    case Repo.get(HeadRow, mission_id) do
      %HeadRow{} = head -> head
      nil -> create_baseline(organization_id, mission_id)
    end
  end

  @doc "Locks the head row for an apply. Must run inside a transaction."
  @spec lock_head(String.t(), String.t()) :: HeadRow.t()
  def lock_head(organization_id, mission_id) do
    ensure_head(organization_id, mission_id)

    HeadRow
    |> where([head], head.mission_id == ^mission_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  @doc """
  Writes revision `head + 1` with its entries and moves the head. Must run inside a transaction
  holding `lock_head/2`.
  """
  @spec record(HeadRow.t(), map(), [map()]) :: {:ok, RevisionRow.t()} | {:error, term()}
  def record(%HeadRow{} = head, attrs, entries) do
    number = head.revision_number + 1
    # #261: a caller may choose the id before its transaction, to prove the revision is its own
    # if the connection drops.
    revision_id = Map.get(attrs, :revision_id) || Ids.new("config_revision")

    revision = %RevisionRow{
      revision_id: revision_id,
      organization_id: head.organization_id,
      mission_id: head.mission_id,
      revision_number: number,
      kind: Map.fetch!(attrs, :kind),
      change_set_id: Map.get(attrs, :change_set_id),
      rolls_back_to: Map.get(attrs, :rolls_back_to),
      applied_by: Map.fetch!(attrs, :applied_by),
      submitted_by: Map.fetch!(attrs, :submitted_by),
      applied_at: Map.fetch!(attrs, :applied_at),
      reason: Map.fetch!(attrs, :reason),
      approvals: Map.get(attrs, :approvals, []),
      summary: Map.fetch!(attrs, :summary),
      entry_count: length(entries),
      activation_id: Map.get(attrs, :activation_id),
      generation: Map.get(attrs, :generation),
      content_sha256: Map.get(attrs, :content_sha256)
    }

    with {:ok, revision} <- Repo.insert(revision),
         {_count, nil} <- insert_entries(revision, entries),
         {1, nil} <- move_head(head, revision) do
      {:ok, revision}
    end
  end

  @spec fetch_revision(String.t(), pos_integer()) :: {:ok, RevisionRow.t()} | {:error, term()}
  def fetch_revision(mission_id, number) do
    case Repo.get_by(RevisionRow, mission_id: mission_id, revision_number: number) do
      nil -> {:error, :revision_not_found}
      revision -> {:ok, revision}
    end
  end

  @spec list_revisions(String.t(), keyword()) :: [RevisionRow.t()]
  def list_revisions(mission_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 25) |> min(200)
    before = Keyword.get(opts, :before)

    RevisionRow
    |> where([revision], revision.mission_id == ^mission_id)
    |> maybe_before(before)
    |> order_by([revision], desc: revision.revision_number)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec entries(String.t()) :: [RevisionEntryRow.t()]
  def entries(revision_id) do
    RevisionEntryRow
    |> where([entry], entry.revision_id == ^revision_id)
    |> order_by([entry], asc: entry.position)
    |> Repo.all()
  end

  @doc "Entries with `from < revision_number <= to`, oldest first."
  @spec entries_between(String.t(), integer(), integer()) :: [RevisionEntryRow.t()]
  def entries_between(mission_id, from, to) do
    RevisionEntryRow
    |> where(
      [entry],
      entry.mission_id == ^mission_id and entry.revision_number > ^from and
        entry.revision_number <= ^to
    )
    |> order_by([entry], asc: entry.revision_number, asc: entry.position)
    |> Repo.all()
  end

  @spec entity_entries(String.t(), String.t(), String.t()) :: [RevisionEntryRow.t()]
  def entity_entries(mission_id, kind, entity_id) do
    RevisionEntryRow
    |> where(
      [entry],
      entry.mission_id == ^mission_id and entry.kind == ^kind and entry.entity_id == ^entity_id
    )
    |> order_by([entry], desc: entry.revision_number, desc: entry.position)
    |> Repo.all()
  end

  defp create_baseline(organization_id, mission_id) do
    revision_id = "config_revision_baseline:" <> mission_id
    now = DateTime.utc_now()

    Repo.insert(
      %RevisionRow{
        revision_id: revision_id,
        organization_id: organization_id,
        mission_id: mission_id,
        revision_number: 1,
        kind: "baseline",
        applied_by: %{"kind" => "system", "id" => "cadence", "name" => "Cadence"},
        submitted_by: %{"kind" => "system", "id" => "cadence", "name" => "Cadence"},
        applied_at: now,
        reason: @baseline_summary,
        summary: @baseline_summary
      },
      # Two first requests race here; the baseline id is deterministic, so any conflict (primary
      # key or revision number) means the other one already wrote it.
      on_conflict: :nothing
    )

    Repo.insert(
      %HeadRow{
        mission_id: mission_id,
        organization_id: organization_id,
        revision_number: 1,
        revision_id: revision_id
      },
      on_conflict: :nothing,
      conflict_target: [:mission_id]
    )

    Repo.get!(HeadRow, mission_id)
  end

  defp insert_entries(_revision, []), do: {0, nil}

  defp insert_entries(revision, entries) do
    rows =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        %{
          entry_id: Ids.new("config_entry"),
          revision_id: revision.revision_id,
          organization_id: revision.organization_id,
          mission_id: revision.mission_id,
          revision_number: revision.revision_number,
          position: index,
          kind: entry.kind,
          entity_id: entry.entity_id,
          op: Atom.to_string(entry.op),
          before: entry.previous,
          after: entry.proposed,
          paths: Document.changed_paths(entry.previous, entry.proposed)
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.reduce({0, nil}, fn chunk, {count, nil} ->
      {inserted, nil} = Repo.insert_all(RevisionEntryRow, chunk)
      {count + inserted, nil}
    end)
  end

  defp move_head(head, revision) do
    HeadRow
    |> where([row], row.mission_id == ^head.mission_id)
    |> Repo.update_all(
      set: [
        revision_number: revision.revision_number,
        revision_id: revision.revision_id,
        updated_at: DateTime.utc_now()
      ]
    )
  end

  defp maybe_before(query, nil), do: query

  defp maybe_before(query, number) when is_integer(number),
    do: where(query, [revision], revision.revision_number < ^number)
end
