defmodule Cadence.Reads.PassReservation do
  @moduledoc """
  L14 / parity A11 (fe-ops, ux U74): a pass's reservation for the pass drawer's Technical
  details, what the legacy reservation review showed: its links (provider, transport, plan,
  requirement, scheduled contact), the requested / provider-confirmed / Cadence-accepted value of
  each provider field, and the reservation's provider audit, newest first, 25 per page.

  A structured or oversized (> 512 bytes) provider value is withheld (its cell `nil`, the row
  `restricted: true`), as the legacy page did. `differs` is true when the three cells aren't all
  equal (a missing value counts; withheld cells compare as withheld).
  Contract: docs/apogee/api/contacts.md § Pass reservation.
  """

  alias Cadence.Control.Contacts
  alias Cadence.GroundNetworks.ProviderAudit

  @fields ~w(provider_contact_ref opportunity_ref spacecraft_ref ground_station_ref antenna_or_service_pool_ref service_profile_ref delivery_profile_ref starts_at ends_at status pass_phase delivery_state status_reason)
  @max_bytes 512

  @spec load(binary(), binary(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, :pass_not_found | :invalid_cursor}
  def load(org, mission, pass_id, audit_cursor \\ nil) do
    with {:reservation, {:ok, r}} <-
           {:reservation, Contacts.fetch_provider_reservation(org, mission, pass_id)},
         {:audit, {:ok, audit}} <-
           {:audit,
            ProviderAudit.list_reservation_page(
              org,
              mission,
              r.provider_reservation_id,
              audit_cursor
            )} do
      {:ok,
       %{
         reservation: reservation(r),
         values: Enum.map(@fields, &value(&1, r)),
         audit: %{entries: Enum.map(audit.entries, &audit/1), next_cursor: audit.next}
       }}
    else
      {:reservation, _missing} -> {:error, :pass_not_found}
      {:audit, _bad_cursor} -> {:error, :invalid_cursor}
    end
  end

  defp reservation(r),
    do: %{
      id: r.provider_reservation_id,
      provider_revision: r.provider_revision,
      lifecycle_state: to_string(r.lifecycle_state),
      provider: %{id: r.provider_id, version: r.provider_version},
      transport: r.transport_id && %{id: r.transport_id, version: r.transport_version},
      plan: r.contact_plan_id && %{id: r.contact_plan_id, version: r.contact_plan_version},
      requirement:
        r.contact_requirement_id &&
          %{id: r.contact_requirement_id, version: r.contact_requirement_version},
      scheduled_contact_id: r.scheduled_contact_id,
      last_reconciled_at: r.last_reconciled_at
    }

  defp value(field, r) do
    cells =
      Enum.map(
        [
          r.requested_snapshot_document,
          r.provider_confirmed_snapshot_document,
          r.cadence_accepted_snapshot_document
        ],
        &cell((&1 || %{})[field])
      )

    [requested, confirmed, accepted] = cells

    %{
      field: field,
      requested_json: shown(requested),
      confirmed_json: shown(confirmed),
      accepted_json: shown(accepted),
      restricted: Enum.any?(cells, &(&1 == :withheld)),
      differs: length(Enum.uniq(cells)) > 1
    }
  end

  # A cell: `nil` (not set), `{:json, text}` (a scalar), or `:withheld`.
  defp cell(nil), do: nil

  defp cell(value) when is_binary(value) do
    if String.valid?(value), do: scalar(value), else: :withheld
  end

  defp cell(value) when is_number(value) or is_boolean(value), do: scalar(value)

  defp cell(_structured), do: :withheld

  defp scalar(value) do
    json = Jason.encode!(value)
    if byte_size(json) <= @max_bytes, do: {:json, json}, else: :withheld
  end

  defp shown({:json, json}), do: json
  defp shown(_none_or_withheld), do: nil

  defp audit(entry),
    do: %{
      id: entry.provider_audit_entry_id,
      action: String.slice(entry.action || "", 0, 120),
      outcome: String.slice(entry.outcome || "", 0, 120),
      recorded_at: entry.recorded_at,
      change_id: entry.references && entry.references.provider_change_id
    }
end
