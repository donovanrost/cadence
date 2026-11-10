defmodule Cadence.Control.UplinkQualification.Booking do
  @moduledoc """
  The provider booking behind an uplink session (#44 D2): from the session's provider basis
  (mission, realized contact) to the provider reservation, its provider contact reference and
  the provider client context. Shared by the qualification policy and its driver so both judge
  the same booking.
  """

  alias Cadence.Contacts
  alias Cadence.Contacts.ProviderClients.Registry
  alias Cadence.Contacts.ProviderReservations
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.CredentialResolver

  @type t :: %{
          organization_id: binary(),
          mission_id: binary(),
          provider_contact_ref: binary(),
          scheduled_contact_id: binary(),
          provider_reservation_id: binary(),
          provider_id: binary(),
          spacecraft_id: binary(),
          ground_station_ref: binary() | nil,
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          context: struct(),
          client: module(),
          call_opts: keyword()
        }

  @spec for_session(map()) :: {:ok, t()} | {:error, term()}
  def for_session(%{mission_id: mission_id, contact_id: realized_id})
      when is_binary(mission_id) and is_binary(realized_id) do
    with {:ok, realized} <- Contacts.fetch_realized_contact(mission_id, realized_id),
         {:ok, scheduled} <-
           Contacts.fetch_scheduled_contact(
             realized.organization_id,
             mission_id,
             realized.scheduled_contact_id
           ),
         {:ok, reservation_id} <- reservation_id(scheduled.metadata),
         {:ok, reservation} <-
           ProviderReservations.fetch(realized.organization_id, mission_id, reservation_id),
         ref when is_binary(ref) <- reservation.provider_contact_ref,
         {:ok, provider} <-
           GroundNetworks.fetch_provider_version(
             realized.organization_id,
             mission_id,
             reservation.provider_id,
             reservation.provider_version
           ),
         {:ok, context} <- GroundNetworks.context_from_provider(provider),
         {:ok, client} <- Registry.fetch(context) do
      {:ok,
       %{
         organization_id: realized.organization_id,
         mission_id: mission_id,
         provider_contact_ref: ref,
         scheduled_contact_id: scheduled.scheduled_contact_id,
         provider_reservation_id: reservation.provider_reservation_id,
         provider_id: reservation.provider_id,
         spacecraft_id: reservation.spacecraft_id,
         ground_station_ref: station_ref(reservation),
         starts_at: reservation.starts_at,
         ends_at: reservation.ends_at,
         context: context,
         client: client,
         call_opts: [credential_resolver: CredentialResolver.resolver([])]
       }}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :uplink_session_not_provider_booked}
    end
  end

  def for_session(_basis), do: {:error, :uplink_session_not_provider_booked}

  @doc "The credential the provider signs attestations with: the one Cadence calls it with."
  @spec credential(t()) :: {:ok, binary()} | {:error, term()}
  def credential(%{context: context, call_opts: opts}) do
    case Keyword.fetch!(opts, :credential_resolver).(context.credential_ref) do
      {:ok, key} when is_binary(key) and key != "" -> {:ok, key}
      _other -> {:error, :provider_credential_unavailable}
    end
  end

  defp station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end

  defp reservation_id(%{"provider_reservation_id" => id}) when is_binary(id), do: {:ok, id}
  defp reservation_id(_metadata), do: {:error, :uplink_session_not_provider_booked}
end
