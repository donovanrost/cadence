defmodule Cadence.Contacts.PassResults do
  @moduledoc """
  Persisted pass results (S9, DECISIONS #47/#48, `docs/apogee/domain/pass-review.md`).

  One row per booked pass, keyed by its provider reservation: planned vs actual AOS/LOS, flown
  seconds, provider-reported volume, and the derived outcome with cause and owner
  (`PassResults.Outcome`). Rows are written by the close-out sweep, which runs after each
  reservation reconciliation pass: cancellations close at once; other passes past LOS ask the
  provider for its contact result and stay `pending_report` until it arrives. Cadence-received
  volume isn't stored here; reads compute it from the archives.
  """

  import Ecto.Query

  require Logger

  alias Cadence.Comms.StationAvailability
  alias Cadence.Contacts
  alias Cadence.Contacts.PassResults.{Outcome, Row}
  alias Cadence.Contacts.ProviderClients.Registry
  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.CredentialResolver
  alias Cadence.Platform.{PassReviewSettings, ScopedReadUpdates}
  alias Cadence.Repo

  @closing ~w(confirmed active completed failed unknown canceled rejected canceling)
  @sweep_limit 200

  @doc """
  Closes out an organization's passes past LOS (or canceled) without a final result. Opts:
  `:received` is `fn mission_id, realized_contact_id -> %{bytes, frames} end`, supplied by the
  composition layer from the archives; `:now`, `:client`.
  """
  @spec close_out(String.t(), keyword()) :: %{recorded: non_neg_integer()}
  def close_out(organization_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    organization_id
    |> due(now)
    |> Enum.count(fn reservation ->
      case record(reservation, Keyword.put(opts, :now, now)) do
        {:ok, _row} ->
          true

        {:error, reason} ->
          Logger.warning(
            "pass result for #{reservation.provider_reservation_id} not recorded: #{inspect(reason)}"
          )

          false
      end
    end)
    |> then(&%{recorded: &1})
  end

  @doc "Records (or refreshes) the result of one booked pass."
  @spec record(ProviderReservation.t(), keyword()) :: {:ok, Row.t()} | {:error, term()}
  def record(%ProviderReservation{} = reservation, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    {result, reported?} =
      if reservation.lifecycle_state in [:canceled, :rejected, :canceling],
        do: {nil, true},
        else: provider_result(reservation, opts)

    %{threshold: threshold} =
      PassReviewSettings.effective(reservation.organization_id, reservation.mission_id)

    scheduled = scheduled_contact(reservation)
    realized_id = scheduled && scheduled.realized_contact_id
    received = received(reservation.mission_id, realized_id, opts)

    verdict =
      Outcome.derive(%{
        lifecycle_state: reservation.lifecycle_state,
        cancel_initiator: cancel_initiator(reservation),
        planned_aos: reservation.starts_at,
        planned_los: reservation.ends_at,
        result: result,
        status_reason: snapshot(reservation)["status_reason"],
        station_window: station_window(reservation),
        threshold: threshold,
        received_frames: received && received.frames,
        now: now
      })

    reservation
    |> attrs(result, verdict, reported?, now)
    |> Map.merge(%{
      realized_contact_id: realized_id,
      received_bytes: received && received.bytes,
      received_frames: received && received.frames
    })
    |> upsert()
    |> published(reservation)
  end

  @doc "Per provider: last report time and pending reports, for K3's freshness panel."
  @spec freshness(String.t(), String.t()) :: [map()]
  def freshness(organization_id, mission_id) do
    Row
    |> where([r], r.organization_id == ^organization_id and r.mission_id == ^mission_id)
    |> group_by([r], r.provider_id)
    |> select([r], %{
      provider_id: r.provider_id,
      last_report_at: max(r.provider_reported_at),
      pending_reports: filter(count(r.provider_reservation_id), r.outcome == "pending_report"),
      oldest_pending_los: filter(min(r.planned_los), r.outcome == "pending_report")
    })
    |> Repo.all()
  end

  # -- internals -------------------------------------------------------------------------------

  defp due(organization_id, now) do
    closed =
      from(r in Row,
        where: not is_nil(r.closed_at),
        select: r.provider_reservation_id
      )

    ProviderReservationRow
    |> where(
      [p],
      p.organization_id == ^organization_id and p.lifecycle_state in ^@closing and
        (p.ends_at < ^now or p.lifecycle_state in ["canceled", "rejected"]) and
        p.provider_reservation_id not in subquery(closed)
    )
    |> order_by([p], asc: p.ends_at)
    |> limit(@sweep_limit)
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
  end

  defp provider_result(reservation, opts) do
    with ref when is_binary(ref) <- reservation.provider_contact_ref,
         {:ok, provider} <-
           GroundNetworks.fetch_provider_version(
             reservation.organization_id,
             reservation.mission_id,
             reservation.provider_id,
             reservation.provider_version
           ),
         {:ok, context} <-
           GroundNetworks.context_from_provider(provider, require_active_grant?: false),
         {:ok, client} <- client(context, opts),
         true <-
           Code.ensure_loaded?(client) and function_exported?(client, :fetch_contact_result, 3),
         {:ok, %{} = result} <-
           client.fetch_contact_result(context, ref,
             credential_resolver: CredentialResolver.resolver([])
           ) do
      {result, true}
    else
      _no_result_yet -> {nil, false}
    end
  end

  defp received(_mission_id, nil, _opts), do: nil

  defp received(mission_id, realized_id, opts) do
    case Keyword.get(opts, :received) do
      fun when is_function(fun, 2) -> fun.(mission_id, realized_id)
      _none -> nil
    end
  end

  defp client(context, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(context)
    end
  end

  defp attrs(reservation, result, verdict, reported?, now) do
    snapshot = snapshot(reservation)

    %{
      provider_reservation_id: reservation.provider_reservation_id,
      organization_id: reservation.organization_id,
      mission_id: reservation.mission_id,
      provider_id: reservation.provider_id,
      scheduled_contact_id: reservation.scheduled_contact_id,
      spacecraft_id: reservation.spacecraft_id,
      ground_station_ref:
        snapshot["ground_station_ref"] || reservation.metadata["ground_station_ref"],
      antenna_ref:
        snapshot["antenna_or_service_pool_ref"] ||
          reservation.metadata["antenna_or_service_pool_ref"],
      contact_plan_id: reservation.contact_plan_id,
      contact_plan_version: reservation.contact_plan_version,
      planned_aos: reservation.starts_at,
      planned_los: reservation.ends_at,
      planned_seconds: DateTime.diff(reservation.ends_at, reservation.starts_at),
      planned_bytes: nil,
      outcome: verdict.outcome,
      cause: verdict.cause,
      cause_source: verdict.cause_source,
      owner: verdict.owner,
      disputable: verdict.disputable,
      provider_revision: reservation.provider_revision,
      closed_at: if(reported?, do: now)
    }
    |> Map.merge(provider_fields(result, now))
  end

  defp provider_fields(nil, _now),
    do: %{
      actual_aos: nil,
      actual_los: nil,
      flown_seconds: nil,
      provider_bytes: nil,
      provider_frames: nil,
      provider_packets: nil,
      observations: %{},
      provider_reported_at: nil,
      result_document: %{}
    }

  defp provider_fields(result, now),
    do: %{
      actual_aos: time(result, "actual_acquisition_at"),
      actual_los: time(result, "actual_loss_at"),
      flown_seconds: Outcome.flown_seconds(result),
      provider_bytes: result["bytes_delivered"],
      provider_frames: result["frames_delivered"],
      provider_packets: result["packets_delivered"],
      observations: result["observations"] || %{},
      provider_reported_at: now,
      result_document: result
    }

  defp upsert(attrs) do
    %Row{}
    |> Row.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, Row.replace_fields()},
      conflict_target: :provider_reservation_id,
      returning: true
    )
  end

  defp published({:ok, row}, reservation) do
    ScopedReadUpdates.publish(
      :pass_results_changed,
      reservation.organization_id,
      reservation.mission_id
    )

    ScopedReadUpdates.publish(
      :contacts_changed,
      reservation.organization_id,
      reservation.mission_id
    )

    {:ok, row}
  end

  defp published(error, _reservation), do: error

  # Cadence marks the cancellations it asks for (ProviderReservations.mark_canceling).
  defp cancel_initiator(%{metadata: %{"cancel_initiator" => "cadence"}}), do: :cadence
  defp cancel_initiator(_reservation), do: :provider

  defp snapshot(reservation), do: reservation.provider_confirmed_snapshot_document || %{}

  defp scheduled_contact(%{scheduled_contact_id: nil}), do: nil

  defp scheduled_contact(reservation) do
    case Contacts.fetch_scheduled_contact(
           reservation.organization_id,
           reservation.mission_id,
           reservation.scheduled_contact_id
         ) do
      {:ok, scheduled} -> scheduled
      _missing -> nil
    end
  end

  defp station_window(reservation) do
    station = snapshot(reservation)["ground_station_ref"]

    reservation.organization_id
    |> StationAvailability.blocking_windows(
      reservation.mission_id,
      reservation.starts_at,
      reservation.ends_at
    )
    |> Map.get(station, [])
    |> StationAvailability.overlaps?(reservation.starts_at, reservation.ends_at)
  end

  defp time(result, key) do
    case DateTime.from_iso8601(result[key] || "") do
      {:ok, time, _} -> time
      _ -> nil
    end
  end
end
