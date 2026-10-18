defmodule Cadence.Contacts.ScheduledContactRevisions do
  @moduledoc "Append-only revision ledger for Scheduled Contact execution projections."

  import Ecto.Query

  alias Cadence.Contacts.{ScheduledContact, ScheduledContactRevision}
  alias Cadence.Control.Contacts.Store.ScheduledContactRevisionRow
  alias Cadence.Repo

  @spec ensure_initial(Ecto.Repo.t(), ScheduledContact.t()) ::
          {:ok, ScheduledContactRevision.t() | nil} | {:error, term()}
  def ensure_initial(repo \\ Repo, contact)

  def ensure_initial(_repo, %ScheduledContact{organization_id: organization_id})
      when organization_id in [nil, ""],
      do: {:ok, nil}

  def ensure_initial(repo, %ScheduledContact{} = contact) do
    revision =
      ScheduledContactRevision.new(%{
        organization_id: contact.organization_id,
        mission_id: contact.mission_id,
        scheduled_contact_id: contact.scheduled_contact_id,
        revision: 1,
        snapshot_document: snapshot(contact),
        reason_document: %{"kind" => "scheduled_contact_created"},
        created_by: "cadence"
      })

    case repo.insert(ScheduledContactRevisionRow.changeset(revision),
           on_conflict: :nothing,
           conflict_target: [:scheduled_contact_id, :revision]
         ) do
      {:ok, _row} ->
        fetch_with_repo(repo, contact.organization_id, contact.scheduled_contact_id, 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch(binary(), binary(), pos_integer()) ::
          {:ok, ScheduledContactRevision.t()} | {:error, :scheduled_contact_revision_not_found}
  def fetch(organization_id, scheduled_contact_id, revision) do
    fetch_with_repo(Repo, organization_id, scheduled_contact_id, revision)
  end

  @spec list(binary(), binary()) :: [ScheduledContactRevision.t()]
  def list(organization_id, scheduled_contact_id) do
    ScheduledContactRevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.scheduled_contact_id == ^scheduled_contact_id
    )
    |> order_by([row], asc: row.revision)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRevisionRow.to_domain/1)
  end

  @doc "Fetch one revision inside an explicit organization and mission."
  def fetch_scoped(org, mission, contact, revision) do
    case Repo.get_by(ScheduledContactRevisionRow,
           organization_id: org,
           mission_id: mission,
           scheduled_contact_id: contact,
           revision: revision
         ) do
      nil -> {:error, :scheduled_contact_revision_not_found}
      row -> {:ok, ScheduledContactRevisionRow.to_domain(row)}
    end
  end

  @doc "Bounded revision history at or below the reviewed revision, with a strict seek cursor."
  def list_page(org, mission, contact, reviewed_revision, before_revision \\ nil)
      when is_integer(reviewed_revision) and reviewed_revision in 1..2_147_483_647 do
    query =
      where(
        ScheduledContactRevisionRow,
        [r],
        r.organization_id == ^org and
          r.mission_id == ^mission and r.scheduled_contact_id == ^contact and
          r.revision <= ^reviewed_revision
      )

    with {:ok, query} <- seek(query, before_revision) do
      rows = query |> order_by([r], desc: r.revision) |> limit(26) |> Repo.all()
      entries = rows |> Enum.take(25) |> Enum.map(&ScheduledContactRevisionRow.to_domain/1)
      {:ok, %{entries: entries, next: if(length(rows) > 25, do: List.last(entries).revision)}}
    end
  end

  defp seek(query, nil), do: {:ok, query}

  defp seek(query, revision) when is_integer(revision) and revision in 1..2_147_483_647,
    do: {:ok, where(query, [r], r.revision < ^revision)}

  defp seek(_, _), do: {:error, :invalid_contact_revision_cursor}

  @spec snapshot(ScheduledContact.t()) :: map()
  def snapshot(%ScheduledContact{} = contact) do
    %{
      "starts_at" => DateTime.to_iso8601(contact.starts_at),
      "ends_at" => contact.ends_at && DateTime.to_iso8601(contact.ends_at),
      "provider_contact_ref" => contact.provider_contact_ref,
      "source_endpoint_refs" => contact.source_endpoint_refs,
      "path_template_ids" => contact.path_template_ids,
      "lifecycle_state" => Atom.to_string(contact.lifecycle_state),
      "metadata" => contact.metadata
    }
  end

  defp fetch_with_repo(repo, organization_id, scheduled_contact_id, revision) do
    case repo.get_by(ScheduledContactRevisionRow,
           organization_id: organization_id,
           scheduled_contact_id: scheduled_contact_id,
           revision: revision
         ) do
      nil -> {:error, :scheduled_contact_revision_not_found}
      row -> {:ok, ScheduledContactRevisionRow.to_domain(row)}
    end
  end
end
