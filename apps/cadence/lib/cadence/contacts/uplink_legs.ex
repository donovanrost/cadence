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

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport, TransportStore}
  alias Cadence.Contacts.{LinkAssignment, LinkAssignmentStore, ProviderReservation}

  @not_booked "uplink not booked"
  @unconfirmed "uplink unconfirmed"

  @doc "The uplink leg to request with a booking at `ground_station_ref`, or nil."
  @spec for_booking(binary(), binary(), binary(), binary() | nil, binary()) :: map() | nil
  def for_booking(organization_id, mission_id, spacecraft_id, ground_station_ref, provider_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission_id, spacecraft_id)
    |> Enum.filter(&primary_uplink?/1)
    |> Enum.find_value(&leg(&1, ground_station_ref, provider_id))
  end

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

      confirmed == "included" ->
        ref = %{
          "path_template_id" => requested["path_template_id"],
          "version" => requested["path_template_version"]
        }

        {[requested["path_template_id"]], [ref], [:telemetry_downlink, :command_window],
         %{"uplink" => %{"booked" => true, "routing_rule_id" => requested["routing_rule_id"]}}}

      # An operator attested the booking (DECISIONS #53); only the provider can confirm the
      # uplink service, so no command window yet.
      attested?(reservation) ->
        {[], [], [:telemetry_downlink],
         %{"uplink" => %{"booked" => false, "reason" => @unconfirmed}}}

      true ->
        reason =
          get_in(reservation.provider_confirmed_snapshot_document, ["uplink", "status_reason"])

        {[], [], [:telemetry_downlink],
         %{"uplink" => %{"booked" => false, "reason" => @not_booked, "provider_reason" => reason}}}
    end
  end

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
    rule.metadata
    |> Map.get("materialized_link_assignment_ids", [])
    |> Enum.find_value({:error, :no_uplink_assignment}, fn id ->
      case LinkAssignmentStore.fetch(rule.organization_id, rule.mission_id, id) do
        {:ok, %LinkAssignment{direction: :uplink} = assignment} -> {:ok, assignment}
        _other -> nil
      end
    end)
  end
end
