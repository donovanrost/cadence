defmodule Cadence.Contacts.ProviderBooking do
  @moduledoc """
  Durable provider reservation saga.

  Cadence writes a `ProviderReservation` before making an external mutation.
  Provider calls happen outside database transactions and every result is
  persisted before a canonical Scheduled Contact is materialized.
  """

  alias Cadence.Contacts

  alias Cadence.Contacts.{
    ProviderClients.Registry,
    ProviderReservation,
    ProviderReservations,
    ScheduledContact
  }

  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    CredentialResolver,
    MissionProvider,
    ProviderContact,
    ProviderError
  }

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @provider_request_fields [
    "opportunity_ref",
    "spacecraft_ref",
    "service_profile_ref",
    "delivery_profile_ref",
    "client_reference",
    "tags"
  ]

  @type booking_result :: %{
          provider_reservation: ProviderReservation.t(),
          scheduled_contact: ScheduledContact.t() | nil
        }

  @spec search(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def search(organization_id, mission_id, provider_id, params, opts \\ []) do
    with {:ok, provider} <-
           fetch_provider(
             organization_id,
             mission_id,
             provider_id,
             Keyword.get(opts, :provider_version)
           ),
         {:ok, context, call_opts} <- provider_context(provider, opts),
         {:ok, client} <- resolve_client(context, opts) do
      client.search_opportunities(context, params, call_opts)
    end
  end

  @spec reserve(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, booking_result()} | {:error, term()}
  def reserve(organization_id, mission_id, provider_id, attrs, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_id) and is_map(attrs) and is_list(opts) do
    with {:ok, provider} <-
           fetch_provider(
             organization_id,
             mission_id,
             provider_id,
             Map.get(attrs, "provider_version") || Map.get(attrs, :provider_version)
           ),
         {:ok, context, call_opts} <- provider_context(provider, opts),
         {:ok, client} <- resolve_client(context, opts),
         {:ok, attempt} <- build_attempt(organization_id, mission_id, provider, attrs),
         {:ok, reservation, outcome} <-
           ProviderReservations.create_attempt_with_outcome(organization_id, attempt) do
      case outcome do
        :existing -> booking_result(reservation)
        :created -> submit_reservation(reservation, context, client, attrs, call_opts)
      end
    end
  end

  @doc "Stage 1 compatibility delegate; new callers should use `reserve/5`."
  @spec book(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, booking_result()} | {:error, term()}
  def book(organization_id, mission_id, provider_id, attrs, opts \\ []) do
    reserve(organization_id, mission_id, provider_id, attrs, opts)
  end

  @spec cancel(binary(), binary(), binary(), keyword()) ::
          {:ok, booking_result()} | {:error, term()}
  def cancel(organization_id, mission_id, provider_reservation_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(provider_reservation_id) and is_list(opts) do
    with {:ok, reservation} <-
           ProviderReservations.mark_canceling(
             organization_id,
             mission_id,
             provider_reservation_id
           ),
         {:ok, provider} <-
           GroundNetworks.fetch_provider_version(
             organization_id,
             mission_id,
             reservation.provider_id,
             reservation.provider_version
           ),
         {:ok, context, call_opts} <- provider_context(provider, opts),
         {:ok, client} <- resolve_client(context, opts),
         {:ok, provider_control_ref} <- require_provider_control_ref(reservation) do
      case client.cancel_contact(context, provider_control_ref, call_opts) do
        {:ok, response} ->
          complete_cancellation(reservation, response)

        {:error, reason} ->
          persist_saga_error(reservation, reason, error_lifecycle(reason))
      end
    end
  end

  defp complete_cancellation(reservation, response) do
    with {:ok, response} <- reservation_result(response),
         :ok <- validate_reservation_result(response),
         {:ok, updated} <-
           ProviderReservations.apply_provider_status(
             reservation.organization_id,
             reservation.mission_id,
             reservation.provider_reservation_id,
             response
           ) do
      booking_result(updated)
    else
      {:error, {:provider_configuration_failure, _reservation, _reason} = failure} ->
        {:error, failure}

      {:error, reason} ->
        persist_saga_error(reservation, reason, :unknown)
    end
  end

  defp submit_reservation(reservation, context, client, _attrs, opts) do
    provider_attrs = %{
      "opportunity_ref" => reservation.provider_opportunity_ref,
      "spacecraft_ref" => reservation.provider_spacecraft_ref,
      "service_profile_ref" => reservation.service_profile_ref["id"],
      "delivery_profile_ref" => reservation.delivery_profile_ref["id"],
      "client_reference" => reservation.idempotency_key,
      "tags" => %{"cadence_mission_ref" => reservation.mission_id}
    }

    call_opts =
      opts
      |> Keyword.put(:idempotency_key, reservation.idempotency_key)
      |> Keyword.put(:contact_window, %{
        starts_at: reservation.starts_at,
        ends_at: reservation.ends_at
      })

    case client.reserve_contact(context, provider_attrs, call_opts) do
      {:ok, response} ->
        with {:ok, response} <- reservation_result(response),
             :ok <- validate_reservation_result(response),
             :ok <- validate_response_matches_attempt(response, reservation),
             {:ok, updated} <-
               ProviderReservations.apply_provider_status(
                 reservation.organization_id,
                 reservation.mission_id,
                 reservation.provider_reservation_id,
                 response
               ) do
          booking_result(updated)
        else
          {:error, {:provider_configuration_failure, _reservation, _reason} = failure} ->
            {:error, failure}

          {:error, reason} ->
            persist_saga_error(reservation, reason, :unknown)
        end

      {:error, reason} ->
        persist_saga_error(reservation, reason, error_lifecycle(reason))
    end
  end

  defp build_attempt(organization_id, mission_id, %MissionProvider{} = provider, attrs) do
    string_attrs = stringify_keys(attrs)

    with {:ok, starts_at} <- parse_time(string_attrs["starts_at"], :starts_at),
         {:ok, ends_at} <- parse_time(string_attrs["ends_at"], :ends_at),
         :ok <- validate_interval(starts_at, ends_at),
         {:ok, opportunity_ref} <- required_binary(string_attrs, "opportunity_ref"),
         {:ok, provider_spacecraft_ref} <- provider_spacecraft_ref(string_attrs),
         {:ok, spacecraft_id} <- canonical_spacecraft_id(string_attrs),
         {:ok, transport_id} <- required_binary(string_attrs, "transport_id"),
         {:ok, transport_version} <- required_positive_integer(string_attrs, "transport_version"),
         {:ok, service_profile_ref} <- exact_profile_ref(string_attrs, "service_profile_ref"),
         {:ok, delivery_profile_ref} <- exact_profile_ref(string_attrs, "delivery_profile_ref"),
         {:ok, provider_profile_id} <- required_binary(string_attrs, "provider_profile_id"),
         {:ok, provider_profile_version} <-
           required_positive_integer(string_attrs, "provider_profile_version"),
         {:ok, source_endpoint_refs} <- required_binary_list(string_attrs, "source_endpoint_refs"),
         {:ok, path_template_ids} <- required_binary_list(string_attrs, "path_template_ids") do
      scheduled_contact_id =
        string_attrs["scheduled_contact_id"] || Ids.new("scheduled_contact")

      provider_reservation_id =
        string_attrs["provider_reservation_id"] || Ids.new("provider_reservation")

      idempotency_key =
        string_attrs["idempotency_key"] || "cadence:#{scheduled_contact_id}"

      request_document = %{
        "provider_request" =>
          %{
            "opportunity_ref" => opportunity_ref,
            "spacecraft_ref" => provider_spacecraft_ref,
            "service_profile_ref" => service_profile_ref["id"],
            "delivery_profile_ref" => delivery_profile_ref["id"],
            "client_reference" => idempotency_key,
            "tags" => %{"cadence_mission_ref" => mission_id}
          }
          |> Map.take(@provider_request_fields),
        "routing" => %{
          "routing_rule_id" => string_attrs["routing_rule_id"],
          "source_endpoint_refs" => source_endpoint_refs,
          "path_template_refs" => path_template_refs(string_attrs, path_template_ids)
        },
        "bindings" => %{
          "provider_ref" => %{"id" => provider.provider_id, "version" => provider.version},
          "transport_ref" => %{"id" => transport_id, "version" => transport_version},
          "service_profile_ref" => service_profile_ref,
          "delivery_profile_ref" => delivery_profile_ref,
          "runtime_provider_profile_ref" => %{
            "id" => provider_profile_id,
            "version" => provider_profile_version
          }
        }
      }

      {:ok,
       ProviderReservation.new(%{
         provider_reservation_id: provider_reservation_id,
         organization_id: organization_id,
         mission_id: mission_id,
         provider_id: provider.provider_id,
         provider_version: provider.version,
         provider_account_id: provider.provider_account_id,
         provider_account_version: provider.provider_account_version,
         provider_account_grant_id: provider.provider_account_grant_id,
         provider_account_grant_version: provider.provider_account_grant_version,
         transport_id: transport_id,
         transport_version: transport_version,
         service_profile_ref: service_profile_ref,
         delivery_profile_ref: delivery_profile_ref,
         provider_profile_id: provider_profile_id,
         provider_profile_version: provider_profile_version,
         scheduled_contact_id: scheduled_contact_id,
         provider_opportunity_ref: opportunity_ref,
         idempotency_key: idempotency_key,
         lifecycle_state: :requesting,
         spacecraft_id: spacecraft_id,
         provider_spacecraft_ref: provider_spacecraft_ref,
         source_endpoint_refs: source_endpoint_refs,
         path_template_ids: path_template_ids,
         starts_at: starts_at,
         ends_at: ends_at,
         request_document: request_document,
         metadata: %{
           "ground_station_ref" => string_attrs["ground_station_ref"],
           "antenna_or_service_pool_ref" => string_attrs["antenna_or_service_pool_ref"],
           "provider_display_name" => provider.display_name,
           "transport_display_name" => string_attrs["transport_display_name"],
           "service_display_name" => string_attrs["service_display_name"],
           "delivery_display_name" => string_attrs["delivery_display_name"],
           "delivery_operator_summary" => string_attrs["delivery_operator_summary"]
         }
       })}
    end
  rescue
    error in [ArgumentError, KeyError] -> {:error, {:invalid_provider_booking, error.message}}
  end

  defp booking_result(reservation) do
    scheduled_contact =
      case Contacts.fetch_scheduled_contact(
             reservation.organization_id,
             reservation.mission_id,
             reservation.scheduled_contact_id
           ) do
        {:ok, scheduled_contact} -> scheduled_contact
        {:error, :scheduled_contact_not_found} -> nil
      end

    {:ok, %{provider_reservation: reservation, scheduled_contact: scheduled_contact}}
  end

  defp persist_saga_error(reservation, reason, lifecycle_state) do
    error_document = %{
      "lifecycle_state" => Atom.to_string(lifecycle_state),
      "reason" => encode_error(reason),
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case ProviderReservations.record_provider_error(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_reservation_id,
           error_document
         ) do
      {:ok, updated} ->
        {:error, {:provider_reservation_not_confirmed, updated}}

      {:error, persistence_reason} ->
        {:error, {:provider_saga_persistence_failed, reason, persistence_reason}}
    end
  end

  defp error_lifecycle(%ProviderError{category: category})
       when category in [:conflict, :no_capacity, :invalid_request],
       do: :rejected

  defp error_lifecycle(%ProviderError{category: :provider_unavailable}), do: :failed
  defp error_lifecycle(_reason), do: :unknown

  defp validate_reservation_result(response) when is_map(response) do
    with {:ok, _id} <- required_binary(response, "id"),
         {:ok, _provider_contact_ref} <- required_binary(response, "provider_contact_ref"),
         {:ok, status} <- required_binary(response, "status"),
         true <- status in ~w(pending confirmed active completed rejected canceled failed),
         {:ok, _starts_at} <- parse_time(response["starts_at"], :starts_at),
         {:ok, _ends_at} <- parse_time(response["ends_at"], :ends_at) do
      :ok
    else
      false -> {:error, {:malformed_provider_response, :status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_response_matches_attempt(response, reservation) do
    with {:ok, response_starts_at} <- parse_time(response["starts_at"], :starts_at),
         {:ok, response_ends_at} <- parse_time(response["ends_at"], :ends_at) do
      if DateTime.compare(response_starts_at, reservation.starts_at) == :eq and
           DateTime.compare(response_ends_at, reservation.ends_at) == :eq do
        :ok
      else
        {:error,
         {:provider_counteroffer_not_supported, response["starts_at"], response["ends_at"]}}
      end
    end
  end

  defp fetch_provider(organization_id, mission_id, provider_id, version)
       when is_integer(version) and version > 0 do
    GroundNetworks.fetch_provider_version(
      organization_id,
      mission_id,
      provider_id,
      version
    )
  end

  defp fetch_provider(_organization_id, _mission_id, _provider_id, version),
    do: {:error, {:invalid_provider_version, version}}

  defp resolve_client(context, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(context)
    end
  end

  defp provider_context(%MissionProvider{} = provider, opts) do
    with {:ok, context} <- GroundNetworks.context_from_provider(provider) do
      call_opts =
        opts
        |> Keyword.drop([:client, :provider_version])
        |> Keyword.put_new(:credential_resolver, CredentialResolver.resolver(opts))

      {:ok, context, call_opts}
    end
  end

  defp reservation_result(%ProviderContact{} = contact),
    do: {:ok, ProviderContact.to_reservation_result(contact)}

  defp reservation_result(response) when is_map(response), do: {:ok, response}
  defp reservation_result(_response), do: {:error, {:malformed_provider_response, :contact}}

  defp encode_error(%ProviderError{} = error), do: ProviderError.to_map(error)
  defp encode_error(reason), do: JsonDocument.encode(reason)

  defp parse_time(%DateTime{} = value, _field), do: {:ok, value}

  defp parse_time(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> {:error, {:invalid_provider_time, field, value}}
    end
  end

  defp parse_time(value, field), do: {:error, {:invalid_provider_time, field, value}}

  defp validate_interval(starts_at, ends_at) do
    if DateTime.before?(starts_at, ends_at), do: :ok, else: {:error, :invalid_contact_interval}
  end

  defp required_binary(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_provider_booking_field, key}}
    end
  end

  defp required_binary_list(map, key) do
    case Map.get(map, key) do
      values when is_list(values) and values != [] ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {:ok, values}
        else
          {:error, {:invalid_provider_booking_field, key}}
        end

      _other ->
        {:error, {:missing_provider_booking_field, key}}
    end
  end

  defp required_positive_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> {:error, {:missing_provider_booking_field, key}}
    end
  end

  defp exact_profile_ref(map, key) do
    case Map.get(map, key) do
      %{} = reference ->
        id = Map.get(reference, "id", Map.get(reference, :id))
        version = Map.get(reference, "version", Map.get(reference, :version))

        if is_binary(id) and id != "" and is_integer(version) and version > 0,
          do: {:ok, %{"id" => id, "version" => version}},
          else: {:error, {:invalid_provider_booking_field, key}}

      _other ->
        {:error, {:missing_provider_booking_field, key}}
    end
  end

  defp provider_spacecraft_ref(attrs) do
    case attrs["provider_spacecraft_ref"] || attrs["spacecraft_id"] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_provider_booking_field, "provider_spacecraft_ref"}}
    end
  end

  defp canonical_spacecraft_id(attrs) do
    case attrs["cadence_spacecraft_id"] || attrs["spacecraft_id"] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_provider_booking_field, "cadence_spacecraft_id"}}
    end
  end

  defp require_provider_control_ref(%ProviderReservation{} = reservation) do
    case reservation.response_document["id"] || reservation.provider_contact_ref do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :provider_contact_reference_unknown}
    end
  end

  defp path_template_refs(attrs, path_template_ids) do
    case attrs["path_template_refs"] do
      refs when is_list(refs) and refs != [] -> refs
      _other -> Enum.map(path_template_ids, &%{"path_template_id" => &1, "version" => 1})
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
