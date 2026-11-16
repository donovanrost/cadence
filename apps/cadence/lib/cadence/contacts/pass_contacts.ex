defmodule Cadence.Contacts.PassContacts do
  @moduledoc """
  What a pass row needs about its contact (U55/U56, ux; api's console reads), in one batch:
  the scheduled contact's state and window, whether its realized contact is live, and how it
  ended (the latest cancel or end-early action: who, when, why, the cause and the provider's
  reason). `window_moves/3` lists the provider's moves of the pass (domain's window-truth
  revisions, `reason_document.kind == "provider_change"`).
  """

  import Ecto.Query

  alias Cadence.Contacts.{ContactAction, ScheduledContactRevisions}
  alias Cadence.Contacts.ContactStore.{ContactActionRow, RealizedContactRow, ScheduledContactRow}
  alias Cadence.Repo

  @ending_kinds ~w(scheduled_contact_canceled realized_contact_ended_early)

  @type fact :: %{
          state: atom(),
          starts_at: DateTime.t() | nil,
          ends_at: DateTime.t() | nil,
          realized_contact_id: binary() | nil,
          live?: boolean(),
          ending: ContactAction.t() | nil,
          canceled_at: DateTime.t() | nil
        }

  @spec facts(binary(), binary(), [binary()]) :: %{binary() => fact()}
  def facts(_org, _mission, []), do: %{}

  def facts(org, mission, scheduled_ids) do
    ids = Enum.uniq(scheduled_ids)

    contacts =
      ScheduledContactRow
      |> where(
        [row],
        row.organization_id == ^org and row.mission_id == ^mission and
          row.scheduled_contact_id in ^ids
      )
      |> Repo.all()
      |> Enum.map(&ScheduledContactRow.to_domain/1)

    live = live_realized(org, mission, Enum.map(contacts, & &1.realized_contact_id))
    endings = latest_endings(org, mission, ids)

    Map.new(contacts, fn contact ->
      {contact.scheduled_contact_id,
       %{
         state: contact.lifecycle_state,
         starts_at: contact.starts_at,
         ends_at: contact.ends_at,
         realized_contact_id: contact.realized_contact_id,
         live?: MapSet.member?(live, contact.realized_contact_id),
         ending: Map.get(endings, contact.scheduled_contact_id),
         canceled_at: canceled_at(contact.metadata)
       }}
    end)
  end

  @doc """
  The provider's moves of a pass, newest first: `[%{at, before, after, classification,
  provider_change_id}]`, `before`/`after` `{starts_at, ends_at}`. A provider-change revision that
  didn't record its window (an approved change, `approval_required`) takes it from the snapshots,
  the one before and its own; a revision that didn't move the window isn't a move and is left out.
  """
  @spec window_moves(binary(), binary() | nil) :: [map()]
  def window_moves(_org, nil), do: []

  def window_moves(org, scheduled_contact_id) do
    revisions = ScheduledContactRevisions.list(org, scheduled_contact_id)

    [nil | revisions]
    |> Enum.zip(revisions)
    |> Enum.filter(fn {_previous, revision} -> reason_kind(revision) == "provider_change" end)
    |> Enum.flat_map(fn {previous, revision} -> move(previous, revision) end)
    |> Enum.sort_by(&DateTime.to_unix(&1.at, :microsecond), :desc)
  end

  defp move(previous, revision) do
    reason = document(revision.reason_document)
    before = window(reason["before"]) || snapshot_window(previous)
    after_window = window(reason["after"]) || snapshot_window(revision)

    if before && after_window && before != after_window do
      [
        %{
          at: revision.created_at,
          before: before,
          after: after_window,
          classification: reason["classification"],
          provider_change_id: revision.provider_reservation_change_id
        }
      ]
    else
      []
    end
  end

  defp snapshot_window(nil), do: nil
  defp snapshot_window(revision), do: window(document(revision.snapshot_document))

  defp window(%{"starts_at" => starts_at, "ends_at" => ends_at}) when is_binary(starts_at),
    do: %{"starts_at" => starts_at, "ends_at" => ends_at}

  defp window(_none), do: nil

  # The lifecycle's own cancel time (lead 11-14: `at` for a cancel with no action record).
  defp canceled_at(metadata) do
    metadata = document(metadata)

    case Map.get(metadata, "canceled_at") || Map.get(metadata, :canceled_at) do
      %DateTime{} = at ->
        at

      at when is_binary(at) ->
        case DateTime.from_iso8601(at) do
          {:ok, parsed, _offset} -> parsed
          _invalid -> nil
        end

      _none ->
        nil
    end
  end

  defp reason_kind(revision), do: document(revision.reason_document)["kind"]

  defp document(%{"value" => %{} = value}), do: value
  defp document(%{} = document), do: document
  defp document(_none), do: %{}

  defp live_realized(org, mission, ids) do
    case Enum.reject(ids, &is_nil/1) do
      [] ->
        MapSet.new()

      ids ->
        from(row in RealizedContactRow,
          where:
            row.organization_id == ^org and row.mission_id == ^mission and
              row.realized_contact_id in ^ids and row.lifecycle_state == "active",
          select: row.realized_contact_id
        )
        |> Repo.all()
        |> MapSet.new()
    end
  end

  defp latest_endings(org, mission, ids) do
    ContactActionRow
    |> where(
      [row],
      row.organization_id == ^org and row.mission_id == ^mission and
        row.scheduled_contact_id in ^ids and row.action_kind in ^@ending_kinds
    )
    |> Repo.all()
    |> Enum.map(&ContactActionRow.to_domain/1)
    |> Enum.group_by(& &1.scheduled_contact_id)
    |> Map.new(fn {id, actions} ->
      {id, Enum.max_by(actions, &DateTime.to_unix(&1.occurred_at, :microsecond))}
    end)
  end
end
