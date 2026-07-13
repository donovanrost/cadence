defmodule Cadence.Contacts.ProviderBooking do
  @moduledoc """
  Coordinates provider reservations with Cadence scheduled contacts.

  The provider reservation is created first. If local persistence fails, the
  provider reservation is canceled as a compensating action.
  """

  alias Cadence.Contacts
  alias Cadence.Contacts.{ProviderClients.Registry, ScheduledContact}
  alias Cadence.Ids

  @spec search(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def search(organization_id, mission_id, provider_profile_id, params, opts \\ []) do
    with {:ok, provider_profile} <-
           Contacts.fetch_provider_profile(organization_id, mission_id, provider_profile_id),
         {:ok, client} <- resolve_client(provider_profile, opts) do
      client.search_opportunities(provider_profile, params, opts)
    end
  end

  @spec book(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{provider_reservation: map(), scheduled_contact: ScheduledContact.t()}}
          | {:error, term()}
  def book(organization_id, mission_id, provider_profile_id, attrs, opts \\ []) do
    with {:ok, provider_profile} <-
           Contacts.fetch_provider_profile(organization_id, mission_id, provider_profile_id),
         {:ok, client} <- resolve_client(provider_profile, opts),
         {:ok, reservation} <-
           client.reserve_contact(
             provider_profile,
             attrs
             |> provider_reservation_attrs()
             |> Map.put("mission_profile_ref", mission_id),
             Keyword.put_new(opts, :idempotency_key, idempotency_key(attrs))
           ),
         {:ok, starts_at} <- parse_time(reservation["starts_at"]),
         {:ok, ends_at} <- parse_time(reservation["ends_at"]) do
      scheduled_contact_attrs =
        %{
          mission_id: mission_id,
          organization_id: organization_id,
          scheduled_contact_id:
            Map.get(attrs, "scheduled_contact_id") || Ids.new("scheduled_contact"),
          source_endpoint_refs: Map.fetch!(attrs, "source_endpoint_refs"),
          contact_intents: Map.get(attrs, "contact_intents", ["telemetry_downlink"]),
          path_template_ids: Map.fetch!(attrs, "path_template_ids"),
          starts_at: starts_at,
          ends_at: ends_at,
          provider_contact_ref: reservation["id"],
          metadata: %{
            "provider_profile_id" => provider_profile_id,
            "provider_reservation" => reservation
          }
        }

      scheduled_contact = ScheduledContact.new(scheduled_contact_attrs)

      case Contacts.persist_scheduled_contact(organization_id, scheduled_contact) do
        {:ok, scheduled_contact} ->
          {:ok, %{provider_reservation: reservation, scheduled_contact: scheduled_contact}}

        {:error, reason} ->
          _compensation = client.cancel_contact(provider_profile, reservation["id"], opts)
          {:error, {:scheduled_contact_persistence_failed, reason}}
      end
    end
  rescue
    KeyError -> {:error, {:invalid_provider_booking, :missing_contact_configuration}}
  end

  @spec cancel(binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel(organization_id, mission_id, provider_profile_id, scheduled_contact_id, opts \\ []) do
    with {:ok, provider_profile} <-
           Contacts.fetch_provider_profile(organization_id, mission_id, provider_profile_id),
         {:ok, client} <- resolve_client(provider_profile, opts),
         {:ok, scheduled_contact} <-
           Contacts.fetch_scheduled_contact(organization_id, mission_id, scheduled_contact_id),
         {:ok, _provider_reservation} <-
           client.cancel_contact(provider_profile, scheduled_contact.provider_contact_ref, opts) do
      Contacts.cancel_scheduled_contact(
        organization_id,
        mission_id,
        scheduled_contact_id,
        actor: %{"kind" => "system", "id" => "provider_booking"},
        reason: "provider_reservation_canceled"
      )
    end
  end

  defp provider_reservation_attrs(attrs) do
    Map.take(attrs, [
      "opportunity_id",
      "run_id",
      "spacecraft_id",
      "ground_station_id",
      "antenna_id",
      "starts_at",
      "ends_at",
      "mission_profile_ref",
      "dataflow_profile_ref",
      "data_plane"
    ])
  end

  defp idempotency_key(attrs) do
    Map.get(attrs, "idempotency_key") ||
      "cadence:#{Map.get(attrs, "scheduled_contact_id", Map.fetch!(attrs, "opportunity_id"))}"
  end

  defp resolve_client(provider_profile, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(provider_profile)
    end
  end

  defp parse_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> {:error, {:invalid_provider_time, value}}
    end
  end
end
