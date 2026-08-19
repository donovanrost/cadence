defmodule CadenceWeb.OpsContactScheduleLive.LiveDeps do
  @moduledoc false

  alias Cadence.Contacts.{ProviderBooking, ProviderReservations, ProviderScheduling}

  @enforce_keys [
    :list_spacecraft,
    :list_ready_routes,
    :resolve_ready_route,
    :search_opportunities,
    :reserve,
    :cancel,
    :list_reservation_rows,
    :list_contact_records,
    :refresh_interval_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          list_spacecraft: function(),
          list_ready_routes: function(),
          resolve_ready_route: function(),
          search_opportunities: function(),
          reserve: function(),
          cancel: function(),
          list_reservation_rows: function(),
          list_contact_records: function(),
          refresh_interval_ms: non_neg_integer()
        }

  @spec from_config() :: t()
  def from_config do
    :cadence_web
    |> Application.get_env(:ops_contact_schedule_live, [])
    |> new()
  end

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      list_spacecraft:
        collaborator(
          opts,
          :list_spacecraft,
          2,
          &Cadence.SpacecraftStore.list_spacecraft/2
        ),
      list_ready_routes:
        collaborator(
          opts,
          :list_ready_routes,
          3,
          &ProviderScheduling.list_ready_downlink_routes/3
        ),
      resolve_ready_route:
        collaborator(
          opts,
          :resolve_ready_route,
          4,
          &ProviderScheduling.resolve_ready_downlink_route/4
        ),
      search_opportunities:
        collaborator(
          opts,
          :search_opportunities,
          4,
          &ProviderScheduling.search_opportunities/4
        ),
      reserve: collaborator(opts, :reserve, 4, &ProviderBooking.reserve/4),
      cancel: collaborator(opts, :cancel, 3, &ProviderBooking.cancel/3),
      list_reservation_rows:
        collaborator(opts, :list_reservation_rows, 2, &default_list_reservation_rows/2),
      list_contact_records:
        collaborator(opts, :list_contact_records, 2, &default_list_contact_records/2),
      refresh_interval_ms: Keyword.get(opts, :refresh_interval_ms, 2_000)
    }
  end

  def list_spacecraft(%__MODULE__{} = deps, organization_id, mission_id) do
    deps.list_spacecraft.(organization_id, mission_id)
  end

  def list_ready_routes(%__MODULE__{} = deps, organization_id, mission_id, spacecraft_id) do
    deps.list_ready_routes.(organization_id, mission_id, spacecraft_id)
  end

  def resolve_ready_route(
        %__MODULE__{} = deps,
        organization_id,
        mission_id,
        spacecraft_id,
        route_key
      ) do
    deps.resolve_ready_route.(organization_id, mission_id, spacecraft_id, route_key)
  end

  def search_opportunities(
        %__MODULE__{} = deps,
        organization_id,
        mission_id,
        route_key,
        window
      ) do
    deps.search_opportunities.(organization_id, mission_id, route_key, window)
  end

  def reserve(%__MODULE__{} = deps, organization_id, mission_id, provider_id, attrs) do
    deps.reserve.(organization_id, mission_id, provider_id, attrs)
  end

  def cancel(%__MODULE__{} = deps, organization_id, mission_id, provider_reservation_id) do
    deps.cancel.(organization_id, mission_id, provider_reservation_id)
  end

  def list_reservation_rows(%__MODULE__{} = deps, organization_id, mission_id) do
    deps.list_reservation_rows.(organization_id, mission_id)
  end

  def list_contact_records(%__MODULE__{} = deps, organization_id, mission_id) do
    deps.list_contact_records.(organization_id, mission_id)
  end

  def refresh_interval_ms(%__MODULE__{} = deps), do: deps.refresh_interval_ms

  defp collaborator(opts, key, arity, default) do
    case Keyword.get(opts, key) do
      callback when is_function(callback, arity) -> callback
      _missing_or_invalid -> default
    end
  end

  defp default_list_reservation_rows(organization_id, mission_id) do
    ProviderReservations.list_for_mission(organization_id, mission_id)
    |> Enum.map(&reservation_row(organization_id, mission_id, &1))
  end

  defp default_list_contact_records(organization_id, mission_id) do
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
end
