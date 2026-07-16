defmodule Cadence.Contacts.ScheduledContactRevisions do
  @moduledoc "Append-only revision ledger for Scheduled Contact execution projections."

  import Ecto.Query

  alias Cadence.Contacts.{ScheduledContact, ScheduledContactRevision}
  alias Cadence.Persistence.Schemas.ScheduledContactRevisionRow
  alias Cadence.Repo

  @spec ensure_initial(Ecto.Repo.t(), ScheduledContact.t()) ::
          {:ok, ScheduledContactRevision.t()} | {:error, term()}
  def ensure_initial(repo \\ Repo, %ScheduledContact{} = contact) do
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
