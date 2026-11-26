defmodule Cadence.Contacts.ProviderChangeAttention do
  @moduledoc """
  The `provider_change` source of the mission attention read (§11 L14, fe-ops' proposal): a
  provider changed a booked pass and someone must decide. Conflicts:

  - `approval_required` (state `pending_approval`): approve or reject before `deadline_at`;
  - `acknowledgment_required`: the provider already applied it; acknowledge;
  - `configuration_failure`: shown, nothing to decide here.

  Nothing to acknowledge in the attention sense: an item is open until its change is decided or
  superseded, then resolves (`resolved_by` the decider, or `system` when superseded).

  A change whose pass has ended (its reservation's `ends_at`) leaves Now but stays on the pass
  (`pass_items/2`, `pass_history/3`). A pending one there is `expired`: it can't be decided any more
  (lead, ux U44; nothing is stored, it's read off the pass's end).
  """

  import Ecto.Query

  alias Cadence.Accounts.MemberNames
  alias Cadence.Contacts.{ProviderChangeApprovals, ProviderReservationChanges}
  alias Cadence.Control.Contacts.Store.{ProviderReservationChangeRow, ProviderReservationRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @source "provider_change"
  @open %{
    "pending_approval" => "approval_required",
    "acknowledgment_required" => "acknowledgment_required",
    "configuration_failure" => "configuration_failure"
  }
  @decided ~w(approved rejected acknowledged superseded)

  # ux U44: the fields a provider changes, as Contacts names them; unknown keys read nil (shown as
  # "Other" with the key).
  @labels %{
    "starts_at" => "AOS",
    "ends_at" => "LOS",
    "ground_station_ref" => "Station",
    "antenna_or_service_pool_ref" => "Antenna",
    "service_profile_ref" => "Service profile",
    "delivery_profile_ref" => "Delivery profile",
    "spacecraft_ref" => "Spacecraft",
    "pass_phase" => "Pass phase",
    "status" => "Status"
  }

  def source, do: @source

  @doc "Now's items: open changes whose pass hasn't ended."
  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    now = DateTime.utc_now()
    org |> open_items(mission, now) |> Enum.reject(&ended?(&1, now))
  end

  @doc "The pass rows' items: every open change, ended passes included (pending ones `expired`)."
  @spec pass_items(binary(), binary()) :: [map()]
  def pass_items(org, mission), do: open_items(org, mission, DateTime.utc_now())

  @doc """
  One pass's provider changes for its history (ux U44), newest first, at most 50: open ones
  (`resolution` nil, a pending one `expired` once the pass has ended) and decided ones with
  `resolution: %{action, by, at, reason}`.
  """
  @spec pass_history(binary(), binary(), binary()) :: [map()]
  def pass_history(org, mission, reservation_id) do
    now = DateTime.utc_now()

    rows =
      ProviderReservationChangeRow
      |> where(
        [c],
        c.organization_id == ^org and c.mission_id == ^mission and
          c.provider_reservation_id == ^reservation_id
      )
      |> order_by([c], desc: c.inserted_at, desc: c.provider_reservation_change_id)
      |> limit(50)
      |> Repo.all()

    reservation = Map.get(reservations(org, mission, rows), reservation_id)
    names = names(org, Enum.map(rows, & &1.decided_by))

    Enum.map(rows, fn row ->
      row
      |> change_view(reservation, now)
      |> Map.merge(%{raised_at: row.inserted_at, resolution: resolution(org, row, names)})
    end)
  end

  defp open_items(org, mission, now) do
    changes = changes(org, mission, Map.keys(@open))
    reservations = reservations(org, mission, changes)

    changes
    |> Enum.map(&open_item(&1, Map.get(reservations, &1.provider_reservation_id), now))
    |> Enum.sort_by(&(&1.deadline_at || &1.raised_at), DateTime)
  end

  defp ended?(%{ends_at: ends_at}, now),
    do: ProviderReservationChanges.pass_ended?(%{ends_at: ends_at}, now)

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    rows =
      ProviderReservationChangeRow
      |> where(
        [c],
        c.organization_id == ^org and c.mission_id == ^mission and c.lifecycle_state in ^@decided and
          c.updated_at >= ^since
      )
      |> Repo.all()

    names = names(org, Enum.map(rows, & &1.decided_by))

    for row <- rows do
      %{
        id: row.provider_reservation_change_id,
        source: @source,
        resolved_by: resolver(row, names),
        action: row.lifecycle_state,
        resolved_at: row.decided_at || row.updated_at,
        # U44: "Approved by Mira K. at 02:31Z: <reason>."
        note: note(org, row)
      }
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission) do
    now = DateTime.utc_now()

    # As Now: a change whose pass has ended isn't counted.
    open =
      from(c in ProviderReservationChangeRow,
        left_join: r in ProviderReservationRow,
        on:
          r.organization_id == c.organization_id and
            r.provider_reservation_id == c.provider_reservation_id,
        where:
          c.organization_id == ^org and c.mission_id == ^mission and
            c.lifecycle_state in ^Map.keys(@open) and (is_nil(r.ends_at) or r.ends_at > ^now)
      )
      |> Repo.aggregate(:count)

    %{open: open, acknowledged: 0}
  end

  @doc """
  One open item by change id (the decision endpoints' answer), or nil. Ended passes included, so
  an acknowledgement can still be made from the pass.
  """
  @spec item(binary(), binary(), binary()) :: map() | nil
  def item(org, mission, change_id) do
    org |> pass_items(mission) |> Enum.find(&(&1.id == change_id))
  end

  defp changes(org, mission, states) do
    ProviderReservationChangeRow
    |> where(
      [c],
      c.organization_id == ^org and c.mission_id == ^mission and c.lifecycle_state in ^states
    )
    |> Repo.all()
  end

  defp reservations(_org, _mission, []), do: %{}

  defp reservations(org, mission, changes) do
    ids = Enum.map(changes, & &1.provider_reservation_id)

    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and r.provider_reservation_id in ^ids
    )
    |> Repo.all()
    |> Map.new(&{&1.provider_reservation_id, ProviderReservationRow.to_domain(&1)})
  end

  defp open_item(change, reservation, now) do
    %{
      id: change.provider_reservation_change_id,
      source: @source,
      conflict: Map.fetch!(@open, change.lifecycle_state),
      state: "open",
      spacecraft_id: reservation && reservation.spacecraft_id,
      contact_id: reservation && reservation.scheduled_contact_id,
      provider_reservation_id: change.provider_reservation_id,
      ground_station_ref: reservation && ground_station_ref(reservation),
      provider_id: reservation && reservation.provider_id,
      starts_at: reservation && reservation.starts_at,
      ends_at: reservation && reservation.ends_at,
      raised_at: change.inserted_at,
      deadline_at: change.deadline_at,
      provider_change: change_view(change, reservation, now)
    }
  end

  defp change_view(change, reservation, now) do
    %{
      id: change.provider_reservation_change_id,
      classification: change.classification,
      state: change.lifecycle_state,
      deadline_at: change.deadline_at,
      provider_revision: change.provider_revision,
      proposal_hash: change.proposal_hash,
      already_effective: change.already_effective,
      # ux U44: pending when the pass ended, so it can't be decided any more.
      expired:
        change.lifecycle_state == "pending_approval" and
          ProviderReservationChanges.pass_ended?(reservation || %{}, now),
      fields: fields(change.changed_fields_document)
    }
  end

  defp resolution(_org, %{lifecycle_state: state}, _names)
       when state in ~w(pending_approval acknowledgment_required configuration_failure),
       do: nil

  defp resolution(org, row, names),
    do: %{
      action: row.lifecycle_state,
      by: resolver(row, names),
      at: row.decided_at || row.updated_at,
      reason: note(org, row)
    }

  defp note(_org, %{lifecycle_state: "superseded"}), do: nil

  defp note(org, row) do
    case ProviderChangeApprovals.fetch(org, row.provider_reservation_change_id) do
      {:ok, approval} -> approval.reason
      _none -> nil
    end
  end

  # 64-bit safe: values travel as JSON text.
  defp fields(document) do
    (JsonDocument.unwrap_value(document) || %{})
    |> Enum.sort_by(fn {field, _values} -> field end)
    |> Enum.map(fn {field, values} ->
      %{
        field: field,
        label: Map.get(@labels, field),
        before_json: Jason.encode!(values["before"]),
        after_json: Jason.encode!(values["after"])
      }
    end)
  end

  defp ground_station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end

  defp resolver(%{lifecycle_state: "superseded"}, _names), do: %{"kind" => "system"}

  # #146 (#468): a person is named, and keeps their id, only while an active member of the
  # mission's organization; anyone else reads id and name nil, never an email.
  defp resolver(%{decided_by: id}, names) when is_binary(id) do
    case Map.fetch(names, id) do
      {:ok, name} -> %{"kind" => "user", "id" => id, "name" => name}
      :error -> %{"kind" => "user", "id" => nil, "name" => nil}
    end
  end

  defp resolver(_row, _names), do: %{"kind" => "system"}

  defp names(org, ids), do: MemberNames.members(org, Enum.filter(ids, &is_binary/1))
end
