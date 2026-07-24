defmodule Cadence.Control.Contacts.ProviderEvents do
  @moduledoc """
  Control-plane handoff from provider events to authoritative Contact state.

  Ground Networks owns durable event delivery. This service owns correlation to
  a provider reservation and reconciliation of the resulting Contacts state.
  """

  alias Cadence.Contacts.{
    ProviderReservation,
    ProviderReservationReconciler,
    ProviderReservations
  }

  @type outcome ::
          {:ok, map()}
          | {:quarantine, term()}
          | {:retry, term()}
          | {:error, term()}

  @spec reconcile_provider_event(map(), keyword()) :: outcome()
  def reconcile_provider_event(entry, opts \\ []) when is_map(entry) and is_list(opts) do
    with {:ok, reservation} <- correlate(entry),
         {:ok, reconciled} <-
           ProviderReservationReconciler.reconcile_reservation(
             reservation,
             provider_opts(opts)
           ),
         :ok <- after_reconcile(entry, reconciled, opts) do
      {:ok, resolution(reconciled)}
    else
      {:error, reason}
      when reason in [:provider_reservation_not_found, :provider_event_correlation_ambiguous] ->
        {:quarantine, reason}

      {:error, %ProviderReservation{}, reason} ->
        {:retry, reason}

      {:error, :injected_after_domain_commit} = injected ->
        injected

      {:error, reason} ->
        {:retry, reason}
    end
  end

  defp correlate(entry) do
    ProviderReservations.resolve_provider_event(
      entry.organization_id,
      entry.provider_account_id,
      entry.provider_account_version,
      entry.resource_id,
      entry.client_reference
    )
  end

  defp after_reconcile(entry, reservation, opts) do
    case Keyword.get(opts, :after_reconcile) do
      callback when is_function(callback, 2) -> callback.(entry, reservation)
      _other -> :ok
    end
  end

  defp resolution(reservation) do
    %{
      mission_id: reservation.mission_id,
      provider_id: reservation.provider_id,
      provider_reservation_id: reservation.provider_reservation_id,
      scheduled_contact_id: reservation.scheduled_contact_id
    }
  end

  defp provider_opts(opts) do
    Keyword.drop(opts, [
      :after_reconcile,
      :limit,
      :max_concurrency,
      :name,
      :now,
      :process_interval_ms,
      :processing_timeout_ms,
      :worker_ref
    ])
  end
end
