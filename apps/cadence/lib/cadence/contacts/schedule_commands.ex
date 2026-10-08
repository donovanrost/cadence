defmodule Cadence.Contacts.ScheduleCommands do
  @moduledoc "Reviewed scheduling commands shared by durable operations and legacy host adapters."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.OpportunityCapability
  alias Cadence.Contacts.{ProviderBooking, ProviderScheduling, ScheduleCancellations}
  alias Cadence.Missions

  @search_fields ~w(spacecraft_id route_key starts_at ends_at)
  @opportunity_max_age_seconds 900

  def execute(scope, mission, action, input) when action in ["search", "reserve", "cancel"] do
    permission = if action == "cancel", do: :manage_missions, else: :operate_mission

    with true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, permission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      dispatch(scope, mission, action, input)
    else
      false -> {:error, :scope_mismatch}
      {:error, _} = error -> error
    end
  end

  defp dispatch(scope, mission_id, "search", params) do
    with {:ok, params} <- exact_map(params, ["contact_search", "route_evidence"]),
         {:ok, form} <- exact_string_map(params["contact_search"], @search_fields),
         true <- is_map(params["route_evidence"]),
         {:ok, window} <- search_window(form),
         {:ok, found} <-
           ProviderScheduling.search_opportunities(
             scope.organization_id,
             mission_id,
             form["route_key"],
             window,
             expected_route: params["route_evidence"]
           ) do
      search_result(found, scope.organization_id, mission_id, form)
    else
      false -> {:error, :malformed_input}
      {:error, _} = error -> error
    end
  end

  defp dispatch(scope, mission_id, "reserve", params) do
    with {:ok, %{"token" => token}} <- exact_ids(params, ["token"]),
         {:ok, payload} <- verify_opportunity(token),
         :ok <- token_scope(payload, scope.organization_id, mission_id),
         :ok <- opportunity_current(payload),
         {:ok, route} <- token_route(payload, scope.organization_id, mission_id),
         :ok <- validate_token_route(route, payload["route"]),
         {:ok, attrs} <- reservation_attrs(payload, route),
         {:ok, booking} <-
           ProviderBooking.reserve(scope.organization_id, mission_id, route.provider_id, attrs) do
      {:ok, booking_result(booking)}
    end
  end

  defp dispatch(scope, mission_id, "cancel", params) do
    with {:ok, booking} <- ScheduleCancellations.execute(scope, mission_id, params),
         do: {:ok, booking_result(booking)}
  end

  defp exact_string_map(value, fields) do
    with {:ok, value} <- exact_map(value, fields),
         true <- Enum.all?(Map.values(value), &is_binary/1) do
      {:ok, value}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp exact_map(value, keys) when is_map(value) do
    if Enum.all?(Map.keys(value), &is_binary/1) and
         MapSet.new(Map.keys(value)) == MapSet.new(keys) do
      {:ok, value}
    else
      {:error, :malformed_input}
    end
  end

  defp exact_map(_value, _keys), do: {:error, :malformed_input}

  defp exact_ids(params, keys) do
    with {:ok, params} <- exact_map(params, keys),
         true <- Enum.all?(Map.values(params), &(is_binary(&1) and &1 != "")) do
      {:ok, params}
    else
      _invalid -> {:error, :malformed_input}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      _invalid -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_datetime}

  defp search_window(params) do
    with {:ok, starts_at} <- parse_search_datetime(params["starts_at"]),
         {:ok, ends_at} <- parse_search_datetime(params["ends_at"]),
         true <- DateTime.before?(starts_at, ends_at) do
      {:ok,
       %{
         "spacecraft_id" => params["spacecraft_id"],
         "starts_at" => DateTime.to_iso8601(starts_at),
         "ends_at" => DateTime.to_iso8601(ends_at)
       }}
    else
      false -> {:error, :invalid_search_window}
      _invalid -> {:error, :invalid_search_datetime}
    end
  end

  defp parse_search_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _invalid -> parse_datetime(value)
    end
  end

  defp verify_opportunity(token) do
    case OpportunityCapability.verify(token, max_age: @opportunity_max_age_seconds) do
      {:ok, payload} when is_map(payload) ->
        case JSONBoundary.validate(payload) do
          :ok -> {:ok, payload}
          {:error, _reason} -> {:error, :malformed_opportunity_token}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp token_scope(payload, organization_id, mission_id) do
    if payload["organization_id"] == organization_id and payload["mission_id"] == mission_id,
      do: :ok,
      else: {:error, :opportunity_scope_mismatch}
  end

  defp token_route(payload, organization_id, mission_id) do
    with spacecraft_id when is_binary(spacecraft_id) <- payload["spacecraft_id"],
         route_key when is_binary(route_key) <- payload["route_key"],
         {:ok, route} <-
           ProviderScheduling.resolve_ready_downlink_route(
             organization_id,
             mission_id,
             spacecraft_id,
             route_key
           ) do
      {:ok, route}
    else
      _invalid -> {:error, :provider_scheduling_route_not_ready}
    end
  end

  defp validate_token_route(route, signed_route) do
    if token_route(route) == signed_route, do: :ok, else: {:error, :route_changed}
  end

  defp token_route(route), do: ProviderScheduling.route_evidence(route)

  defp opportunity_current(%{
         "opportunity" => %{"expires_at" => expires, "availability" => availability}
       }) do
    with true <- is_binary(expires) and availability in ["available", "limited"],
         {:ok, deadline, _} <- DateTime.from_iso8601(expires),
         true <- DateTime.after?(deadline, DateTime.utc_now()),
         do: :ok,
         else: (_ -> {:error, :opportunity_expired_or_unavailable})
  end

  defp opportunity_current(_), do: {:error, :opportunity_expired_or_unavailable}

  @doc false
  def reservation_identity(scope, mission, %{"token" => token} = input)
      when map_size(input) == 1 do
    with {:ok, payload} <- verify_opportunity(token),
         :ok <- token_scope(payload, scope.organization_id, mission),
         :ok <- opportunity_current(payload),
         {:ok, route} <- token_route(payload, scope.organization_id, mission),
         :ok <- validate_token_route(route, payload["route"]),
         {:ok, attrs} <- reservation_attrs(payload, route) do
      {:ok, attrs["provider_reservation_id"]}
    end
  end

  def reservation_identity(_, _, _), do: {:error, :malformed_input}

  defp reservation_attrs(payload, route) do
    with %{"id" => opportunity_id} = opportunity when is_binary(opportunity_id) <-
           payload["opportunity"],
         true <- is_map(payload["route"]) do
      suffix = stable_booking_suffix(payload)

      {:ok,
       opportunity
       |> Map.take([
         "id",
         "ground_station_ref",
         "antenna_or_service_pool_ref",
         "starts_at",
         "ends_at"
       ])
       |> Map.put("opportunity_ref", opportunity_id)
       |> Map.put("provider_reservation_id", "provider_reservation_#{suffix}")
       |> Map.put("scheduled_contact_id", "scheduled_contact_#{suffix}")
       |> Map.put("idempotency_key", "cadence:contact:#{suffix}")
       |> Map.put("provider_version", route.provider_version)
       |> Map.put("transport_id", route.transport_id)
       |> Map.put("transport_version", route.transport_version)
       |> Map.put("service_profile_ref", route.service_profile_ref)
       |> Map.put("delivery_profile_ref", route.delivery_profile_ref)
       |> Map.put("provider_profile_id", route.provider_profile_id)
       |> Map.put("provider_profile_version", route.provider_profile_version)
       |> Map.put("routing_rule_id", route.routing_rule_id)
       |> Map.put("transport_display_name", route.transport_display_name)
       |> Map.put("service_display_name", route.service_display_name)
       |> Map.put("delivery_display_name", route.delivery_display_name)
       |> Map.put("delivery_operator_summary", route.delivery_operator_summary)
       |> Map.put("cadence_spacecraft_id", route.spacecraft_id)
       |> Map.put("provider_spacecraft_ref", route.provider_spacecraft_ref)
       |> Map.put("source_endpoint_refs", [route.source_endpoint_id])
       |> Map.put("path_template_ids", [route.path_template_id])
       |> Map.put("path_template_refs", [
         %{"path_template_id" => route.path_template_id, "version" => route.path_template_version}
       ])}
    else
      _invalid -> {:error, :malformed_opportunity_token}
    end
  end

  defp search_result(%{route: route, opportunities: opportunities} = found, org, mission, form) do
    result = %{
      "contract_version" => 1,
      "context" => %{"organization_id" => org, "mission_id" => mission},
      "search" => form,
      "route" => ProviderScheduling.route_summary(route),
      "truncated" => Map.get(found, :truncated, false),
      "opportunities" =>
        Enum.map(opportunities, fn o ->
          %{
            "id" => o["id"],
            "starts_at" => o["starts_at"],
            "ends_at" => o["ends_at"],
            "expires_at" => capability_expiry(o),
            "availability" => o["availability"],
            "synthetic" => o["synthetic"],
            "station" => o["ground_station_ref"],
            "antenna" => o["antenna_or_service_pool_ref"],
            "cost" => cost(get_in(o, ["extensions", "cost"])),
            "token" => OpportunityCapability.sign(opportunity_payload(o, route, org, mission))
          }
        end)
    }

    bounded_search_result(result)
  end

  defp bounded_search_result(result) do
    base = Map.put(result, "opportunities", [])

    bounded =
      Enum.reduce_while(result["opportunities"], base, fn opportunity, acc ->
        candidate = Map.update!(acc, "opportunities", &(&1 ++ [opportunity]))

        if bounded_search_output?(candidate),
          do: {:cont, candidate},
          else: {:halt, Map.put(acc, "truncated", true)}
      end)

    case JSONBoundary.safe_trusted_output(bounded) do
      {:ok, safe} -> {:ok, safe}
      {:error, _} -> {:error, :opportunity_response_unavailable}
    end
  end

  defp bounded_search_output?(candidate) do
    case JSONBoundary.safe_trusted_output(candidate) do
      {:ok, safe} -> byte_size(Jason.encode!(safe)) <= 60_000
      {:error, _} -> false
    end
  end

  defp capability_expiry(opportunity) do
    {:ok, provider_expiry, _} = DateTime.from_iso8601(opportunity["expires_at"])

    capability_expiry =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(@opportunity_max_age_seconds)

    if DateTime.before?(provider_expiry, capability_expiry),
      do: DateTime.to_iso8601(provider_expiry),
      else: DateTime.to_iso8601(capability_expiry)
  end

  defp cost(v) when is_number(v), do: v
  defp cost(_), do: nil

  defp opportunity_payload(opportunity, route, org, mission),
    do: %{
      "organization_id" => org,
      "mission_id" => mission,
      "spacecraft_id" => route.spacecraft_id,
      "route_key" => route.route_key,
      "route" => token_route(route),
      "opportunity" =>
        Map.take(
          opportunity,
          ~w(id ground_station_ref antenna_or_service_pool_ref starts_at ends_at expires_at availability)
        )
    }

  defp stable_booking_suffix(payload) do
    [
      payload["organization_id"],
      payload["mission_id"],
      payload["route_key"],
      payload["opportunity"]["id"]
    ]
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 24)
  end

  defp booking_result(%{provider_reservation: reservation, scheduled_contact: scheduled}) do
    %{
      "providerReservationId" => reservation.provider_reservation_id,
      "providerRevision" => reservation.provider_revision,
      "lifecycleState" => Atom.to_string(reservation.lifecycle_state),
      "scheduledContactId" => if(scheduled, do: scheduled.scheduled_contact_id, else: nil)
    }
  end
end
