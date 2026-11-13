defmodule Cadence.Contacts.ProviderChangeAttention do
  @moduledoc """
  The `provider_change` source of the mission attention read (§11 L14, fe-ops' proposal): a
  provider changed a booked pass and someone must decide. Conflicts:

  - `approval_required` (state `pending_approval`): approve or reject before `deadline_at`;
  - `acknowledgment_required`: the provider already applied it; acknowledge;
  - `configuration_failure`: shown, nothing to decide here.

  Nothing to acknowledge in the attention sense: an item is open until its change is decided or
  superseded, then resolves (`resolved_by` the decider, or `system` when superseded).
  """

  import Ecto.Query

  alias Cadence.Accounts
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

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    changes = changes(org, mission, Map.keys(@open))
    reservations = reservations(org, mission, changes)

    changes
    |> Enum.map(&item(&1, Map.get(reservations, &1.provider_reservation_id)))
    |> Enum.sort_by(&(&1.deadline_at || &1.raised_at), DateTime)
  end

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

    names = names(Enum.map(rows, & &1.decided_by))

    for row <- rows do
      %{
        id: row.provider_reservation_change_id,
        source: @source,
        resolved_by: resolver(row, names),
        action: row.lifecycle_state,
        resolved_at: row.decided_at || row.updated_at
      }
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission) do
    open =
      ProviderReservationChangeRow
      |> where(
        [c],
        c.organization_id == ^org and c.mission_id == ^mission and
          c.lifecycle_state in ^Map.keys(@open)
      )
      |> Repo.aggregate(:count)

    %{open: open, acknowledged: 0}
  end

  @doc "One open item by change id (the decision endpoints' answer), or nil."
  @spec item(binary(), binary(), binary()) :: map() | nil
  def item(org, mission, change_id) do
    org |> items(mission) |> Enum.find(&(&1.id == change_id))
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

  defp item(change, reservation) do
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
      provider_change: %{
        id: change.provider_reservation_change_id,
        classification: change.classification,
        state: change.lifecycle_state,
        deadline_at: change.deadline_at,
        provider_revision: change.provider_revision,
        proposal_hash: change.proposal_hash,
        already_effective: change.already_effective,
        fields: fields(change.changed_fields_document)
      }
    }
  end

  # 64-bit safe: values travel as JSON text.
  defp fields(document) do
    (JsonDocument.unwrap_value(document) || %{})
    |> Enum.sort_by(fn {field, _values} -> field end)
    |> Enum.map(fn {field, values} ->
      %{
        field: field,
        label: nil,
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

  defp resolver(%{decided_by: id}, names) when is_binary(id),
    do: %{"kind" => "user", "id" => id, "name" => Map.get(names, id)}

  defp resolver(_row, _names), do: %{"kind" => "system"}

  defp names(ids) do
    for id <- ids, is_binary(id), uniq: true, into: %{} do
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _not_a_user -> {id, nil}
      end
    end
  end
end
