defmodule CadenceWeb.OpsContactScheduleLive.LiveDeps do
  @moduledoc false

  alias Cadence.Contacts.{ProviderBooking, ProviderReservations, ProviderScheduling}

  def list_spacecraft(organization_id, mission_id) do
    call(:list_spacecraft, [organization_id, mission_id], fn ->
      Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id)
    end)
  end

  def list_ready_routes(organization_id, mission_id, spacecraft_id) do
    call(:list_ready_routes, [organization_id, mission_id, spacecraft_id], fn ->
      ProviderScheduling.list_ready_downlink_routes(organization_id, mission_id, spacecraft_id)
    end)
  end

  def resolve_ready_route(organization_id, mission_id, spacecraft_id, route_key) do
    call(
      :resolve_ready_route,
      [organization_id, mission_id, spacecraft_id, route_key],
      fn ->
        ProviderScheduling.resolve_ready_downlink_route(
          organization_id,
          mission_id,
          spacecraft_id,
          route_key
        )
      end
    )
  end

  def search_opportunities(organization_id, mission_id, route_key, window) do
    call(:search_opportunities, [organization_id, mission_id, route_key, window], fn ->
      ProviderScheduling.search_opportunities(organization_id, mission_id, route_key, window)
    end)
  end

  def reserve(organization_id, mission_id, provider_id, attrs) do
    call(:reserve, [organization_id, mission_id, provider_id, attrs], fn ->
      ProviderBooking.reserve(organization_id, mission_id, provider_id, attrs)
    end)
  end

  def cancel(organization_id, mission_id, provider_reservation_id) do
    call(:cancel, [organization_id, mission_id, provider_reservation_id], fn ->
      ProviderBooking.cancel(organization_id, mission_id, provider_reservation_id)
    end)
  end

  def list_reservation_rows(organization_id, mission_id) do
    call(:list_reservation_rows, [organization_id, mission_id], fn ->
      ProviderReservations.list_for_mission(organization_id, mission_id)
      |> Enum.map(&reservation_row(organization_id, mission_id, &1))
    end)
  end

  def list_contact_records(organization_id, mission_id) do
    call(:list_contact_records, [organization_id, mission_id], fn ->
      scheduled_contacts = Cadence.Contacts.list_scheduled_contacts(organization_id, mission_id)
      realized_contacts = Cadence.Contacts.list_realized_contacts(organization_id, mission_id)
      realized_by_scheduled = Enum.group_by(realized_contacts, & &1.scheduled_contact_id)

      scheduled_rows =
        Enum.map(scheduled_contacts, fn scheduled_contact ->
          realized_contact =
            realized_contacts
            |> Enum.find(&(&1.realized_contact_id == scheduled_contact.realized_contact_id))
            |> then(
              &(&1 ||
                  List.first(
                    Map.get(realized_by_scheduled, scheduled_contact.scheduled_contact_id, [])
                  ))
            )

          contact_record_row(scheduled_contact, realized_contact)
        end)

      scheduled_ids = MapSet.new(scheduled_contacts, & &1.scheduled_contact_id)

      orphan_realized_rows =
        realized_contacts
        |> Enum.reject(&MapSet.member?(scheduled_ids, &1.scheduled_contact_id))
        |> Enum.map(&contact_record_row(nil, &1))

      (scheduled_rows ++ orphan_realized_rows)
      |> Enum.sort_by(&contact_sort_time/1, {:desc, DateTime})
    end)
  end

  def refresh_interval_ms do
    config() |> Keyword.get(:refresh_interval_ms, 2_000)
  end

  defp call(key, args, default) do
    case Keyword.get(config(), key) do
      fun when is_function(fun) -> apply(fun, args)
      _other -> default.()
    end
  end

  defp reservation_row(organization_id, mission_id, reservation) do
    scheduled_contact =
      case Cadence.Contacts.fetch_scheduled_contact(
             organization_id,
             mission_id,
             reservation.scheduled_contact_id
           ) do
        {:ok, contact} -> contact
        {:error, :scheduled_contact_not_found} -> nil
      end

    %{reservation: reservation, scheduled_contact: scheduled_contact}
  end

  defp contact_record_row(scheduled_contact, realized_contact) do
    %{
      canonical_id:
        if(realized_contact,
          do: realized_contact.realized_contact_id,
          else: scheduled_contact.scheduled_contact_id
        ),
      scheduled_contact: scheduled_contact,
      realized_contact: realized_contact,
      starts_at: contact_start(scheduled_contact, realized_contact),
      ends_at: contact_end(scheduled_contact, realized_contact),
      lifecycle_state:
        if(realized_contact,
          do: realized_contact.lifecycle_state,
          else: scheduled_contact.lifecycle_state
        ),
      source_endpoint_refs:
        (if(scheduled_contact, do: scheduled_contact.source_endpoint_refs, else: []) ++
           if(realized_contact, do: realized_contact.source_endpoint_refs, else: []))
        |> Enum.uniq(),
      contact_intents:
        (if(scheduled_contact, do: scheduled_contact.contact_intents, else: []) ++
           if(realized_contact, do: realized_contact.contact_intents, else: []))
        |> Enum.uniq()
    }
  end

  defp contact_start(scheduled_contact, realized_contact) do
    (realized_contact && (realized_contact.realized_at || realized_contact.initial_time)) ||
      (scheduled_contact && scheduled_contact.starts_at)
  end

  defp contact_end(scheduled_contact, realized_contact) do
    realized_end(realized_contact) || (scheduled_contact && scheduled_contact.ends_at)
  end

  defp realized_end(nil), do: nil

  defp realized_end(realized_contact) do
    metadata = realized_contact.metadata

    (metadata["completed_at"] || metadata["stopped_at"] || metadata["ended_at"])
    |> parse_datetime()
  end

  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp contact_sort_time(%{starts_at: %DateTime{} = starts_at}), do: starts_at
  defp contact_sort_time(_row), do: ~U[1970-01-01 00:00:00Z]

  defp config, do: Application.get_env(:cadence_web, :ops_contact_schedule_live, [])
end
