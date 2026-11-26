defmodule Cadence.Contacts.UplinkLegs do
  @moduledoc """
  The uplink leg of a provider booking (#44, DECISIONS #46).

  A pass is booked with an uplink leg when the spacecraft's primary outbound route lands at the
  pass's station on a transport of the same provider. The provider confirms the leg
  (`"included"`) or rejects it. A scheduled contact carries the uplink path and
  `:command_window` **only** when the leg was both requested and confirmed; otherwise it stays
  downlink-only and records why (`"uplink not booked"`). Contacts already scheduled keep their
  snapshot.
  """

  import Ecto.Query

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport, TransportStore}
  alias Cadence.Contacts.{LinkAssignment, LinkAssignmentStore, ProviderReservation}
  alias Cadence.Control.Contacts.Store.{ProviderReservationChangeRow, ProviderReservationRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @not_booked "uplink not booked"
  @unconfirmed "uplink unconfirmed"
  @provider_confirmed [:confirmed, :active, :completed]

  @doc """
  A16b: the providers through which the spacecraft has a primary uplink path at some station
  (its provider-managed transports), and the stations each pins. `%{provider_id => [station_ref]}`.
  """
  @spec uplink_stations(binary(), binary(), binary()) :: %{binary() => [binary()]}
  def uplink_stations(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission_id, spacecraft_id)
    |> Enum.filter(&primary_uplink?/1)
    |> Enum.flat_map(fn rule ->
      case TransportStore.fetch_transport_version(
             rule.organization_id,
             rule.mission_id,
             rule.transport_id,
             rule.transport_version
           ) do
        {:ok, %Transport{origin: :provider_managed, mission_provider_id: provider} = transport}
        when is_binary(provider) ->
          [{provider, rule.ground_station_id || transport.ground_station_id}]

        _other ->
          []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "The uplink leg to request with a booking at `ground_station_ref`, or nil."
  @spec for_booking(binary(), binary(), binary(), binary() | nil, binary()) :: map() | nil
  def for_booking(organization_id, mission_id, spacecraft_id, ground_station_ref, provider_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission_id, spacecraft_id)
    |> Enum.filter(&primary_uplink?/1)
    |> Enum.find_value(&leg(&1, ground_station_ref, provider_id))
  end

  @doc "The `{spacecraft_id, station_ref, provider_id}` keys with a bookable primary uplink."
  def booking_keys(_org, _mission, []), do: MapSet.new()

  def booking_keys(org, mission, ids) do
    rules =
      org
      |> RoutingRuleStore.list_routing_rules_for_spacecrafts(mission, ids)
      |> Map.values()
      |> List.flatten()
      |> Enum.filter(&primary_uplink?/1)

    transports =
      TransportStore.fetch_transport_versions(
        org,
        mission,
        Enum.map(rules, &{&1.transport_id, &1.transport_version})
      )

    assignments =
      LinkAssignmentStore.fetch_many(org, mission, Enum.flat_map(rules, &assignment_ids/1))

    for rule <- rules,
        %Transport{origin: :provider_managed} = transport <- [
          transports[{rule.transport_id, rule.transport_version}]
        ],
        Enum.any?(
          assignment_ids(rule),
          &match?(%LinkAssignment{direction: :uplink}, assignments[&1])
        ),
        into: MapSet.new() do
      {rule.spacecraft_id, rule.ground_station_id || transport.ground_station_id,
       transport.mission_provider_id}
    end
  end

  defp assignment_ids(rule), do: Map.get(rule.metadata, "materialized_link_assignment_ids", [])

  @doc """
  The scheduled-contact fields for a confirmed reservation: `{extra_path_ids, extra_refs,
  intents, metadata}`.
  """
  @spec scheduled_fields(ProviderReservation.t()) :: {[binary()], [map()], [atom()], map()}
  def scheduled_fields(%ProviderReservation{} = reservation) do
    {ids, refs, intents, metadata} = leg_fields(reservation)

    if attested?(reservation),
      do: {ids, refs, intents, Map.put(metadata, "booking_evidence", "operator_attested")},
      else: {ids, refs, intents, metadata}
  end

  defp leg_fields(reservation) do
    requested = get_in(reservation.request_document, ["uplink"])
    confirmed = get_in(reservation.provider_confirmed_snapshot_document, ["uplink", "status"])

    cond do
      is_nil(requested) ->
        {[], [], [:telemetry_downlink], %{}}

      # An operator attested the booking (DECISIONS #53) and the provider hasn't confirmed it:
      # an `included` leg in a pending snapshot isn't the provider confirming uplink service,
      # so no command window yet (#55 adds it when the provider confirms the booking).
      attested?(reservation) and reservation.lifecycle_state not in @provider_confirmed ->
        {[], [], [:telemetry_downlink],
         %{"uplink" => %{"booked" => false, "reason" => @unconfirmed}}}

      confirmed == "included" ->
        ref = %{
          "path_template_id" => requested["path_template_id"],
          "version" => requested["path_template_version"]
        }

        {[requested["path_template_id"]], [ref], [:telemetry_downlink, :command_window],
         %{"uplink" => %{"booked" => true, "routing_rule_id" => requested["routing_rule_id"]}}}

      true ->
        reason =
          get_in(reservation.provider_confirmed_snapshot_document, ["uplink", "status_reason"])

        {[], [], [:telemetry_downlink],
         %{"uplink" => %{"booked" => false, "reason" => @not_booked, "provider_reason" => reason}}}
    end
  end

  # Changes whose terms Cadence has taken on: the accepted snapshot follows them.
  @accepted_change_states ~w(observed policy_accepted approved acknowledged)

  @doc """
  Whether the booking asked for an uplink leg that Cadence's accepted terms no longer include:
  the provider won't carry the uplink, so the pass has no command window (director, 11-14). The
  scheduled contact keeps its snapshot (#46); releases check this instead.
  """
  @spec dropped?(ProviderReservation.t()) :: boolean()
  def dropped?(%ProviderReservation{} = reservation) do
    status = uplink_status(reservation.cadence_accepted_snapshot_document)

    is_map(get_in(reservation.request_document || %{}, ["uplink"])) and
      status not in [nil, "included"]
  end

  @doc """
  The dropped uplink legs among `reservation_ids`, with the accepted change that dropped each:
  `%{reservation_id => %{at, change_id, provider_id, reason}}` (`at` is when Cadence accepted
  it; `reason` the provider's status_reason, if any). Reservations whose leg is fine are absent.
  """
  @spec drops(binary(), binary(), [binary()]) :: %{binary() => map()}
  def drops(_org, _mission, []), do: %{}

  def drops(org, mission, reservation_ids) when is_list(reservation_ids) do
    dropped =
      from(row in ProviderReservationRow,
        where:
          row.organization_id == ^org and row.mission_id == ^mission and
            row.provider_reservation_id in ^reservation_ids
      )
      |> Repo.all()
      |> Enum.map(&ProviderReservationRow.to_domain/1)
      |> Enum.filter(&dropped?/1)

    changes = drop_changes(org, mission, Enum.map(dropped, & &1.provider_reservation_id))

    Map.new(dropped, fn reservation ->
      change = Map.get(changes, reservation.provider_reservation_id)

      {reservation.provider_reservation_id,
       %{
         at: change && (change.decided_at || change.inserted_at),
         change_id: change && change.provider_reservation_change_id,
         provider_id: reservation.provider_id,
         reason:
           get_in(reservation.cadence_accepted_snapshot_document || %{}, [
             "uplink",
             "status_reason"
           ])
       }}
    end)
  end

  # The latest accepted change per reservation that took the leg out of "included".
  defp drop_changes(_org, _mission, []), do: %{}

  defp drop_changes(org, mission, ids) do
    from(row in ProviderReservationChangeRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.provider_reservation_id in ^ids and row.lifecycle_state in ^@accepted_change_states,
      order_by: [desc: row.provider_revision]
    )
    |> Repo.all()
    |> Enum.filter(fn row ->
      uplink_status(JsonDocument.unwrap_value(row.before_snapshot_document)) == "included" and
        uplink_status(JsonDocument.unwrap_value(row.after_snapshot_document)) not in [
          nil,
          "included"
        ]
    end)
    |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.provider_reservation_id, row) end)
  end

  defp uplink_status(%{"value" => %{} = snapshot}), do: uplink_status(snapshot)
  defp uplink_status(%{"uplink" => %{"status" => status}}), do: status
  defp uplink_status(_snapshot), do: nil

  defp attested?(%ProviderReservation{
         metadata: %{"operator_resolution" => %{"action" => "booked"}}
       }),
       do: true

  defp attested?(_reservation), do: false

  defp primary_uplink?(%RoutingRule{} = rule) do
    rule.lifecycle_state == :active and rule.enabled? and rule.role == :primary and
      rule.direction in [:outbound, :bidirectional]
  end

  defp leg(rule, ground_station_ref, provider_id) do
    with {:ok, %Transport{origin: :provider_managed} = transport} <-
           TransportStore.fetch_transport_version(
             rule.organization_id,
             rule.mission_id,
             rule.transport_id,
             rule.transport_version
           ),
         true <- transport.mission_provider_id == provider_id,
         true <- (rule.ground_station_id || transport.ground_station_id) == ground_station_ref,
         {:ok, assignment} <- uplink_assignment(rule) do
      %{
        "routing_rule_id" => rule.routing_rule_id,
        "transport_id" => transport.transport_id,
        "transport_version" => transport.version,
        "service_profile_ref" => transport.service_profile_ref,
        "delivery_profile_ref" => transport.delivery_profile_ref,
        "path_template_id" => assignment.path_template_id,
        "path_template_version" => assignment.path_template_version
      }
    else
      _not_this_rule -> nil
    end
  end

  defp uplink_assignment(rule) do
    rule
    |> assignment_ids()
    |> Enum.find_value({:error, :no_uplink_assignment}, fn id ->
      case LinkAssignmentStore.fetch(rule.organization_id, rule.mission_id, id) do
        {:ok, %LinkAssignment{direction: :uplink} = assignment} -> {:ok, assignment}
        _other -> nil
      end
    end)
  end
end
