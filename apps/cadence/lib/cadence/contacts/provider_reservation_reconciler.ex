defmodule Cadence.Contacts.ProviderReservationReconciler do
  @moduledoc """
  Safety poller that converges durable provider reservations.

  The process stores only polling cadence. Reservation truth, idempotency, and
  lifecycle evidence remain in Postgres and are re-read after every restart.
  """

  use GenServer

  alias Cadence.Contacts.{ProviderClients.Registry, ProviderReservations}
  alias Cadence.Organizations
  alias Cadence.Persistence.JsonDocument

  @default_poll_interval_ms 5_000
  @default_backoff_ms 5_000
  @default_max_concurrency 4

  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec reconcile_now(GenServer.server()) :: {:ok, map()}
  def reconcile_now(server \\ __MODULE__), do: GenServer.call(server, :reconcile_now, :infinity)

  @spec reconcile_due(binary(), keyword()) :: {:ok, map()}
  def reconcile_due(organization_id, opts)
      when is_binary(organization_id) and is_list(opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    backoff_ms = Keyword.get(opts, :backoff_ms, @default_backoff_ms)
    due_before = DateTime.add(now, -backoff_ms, :millisecond)

    reservations =
      ProviderReservations.list_due_for_reconciliation(
        organization_id,
        mission_id: Keyword.get(opts, :mission_id),
        due_before: due_before,
        limit: Keyword.get(opts, :limit, 100)
      )

    results =
      reservations
      |> Task.async_stream(
        &reconcile_one(&1, opts),
        max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:reconciliation_task_exit, reason}}
      end)

    {:ok, summarize(results)}
  end

  @spec reconcile_all(keyword()) :: {:ok, map()}
  def reconcile_all(opts \\ []) when is_list(opts) do
    summaries =
      Organizations.list_organizations()
      |> Enum.map(fn organization ->
        {:ok, summary} = reconcile_due(organization.organization_id, opts)
        summary
      end)

    {:ok,
     Enum.reduce(summaries, empty_summary(), fn summary, acc ->
       Map.merge(acc, summary, fn
         :results, left, right -> left ++ right
         _key, left, right -> left + right
       end)
     end)}
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :safety_poll_interval_ms, @default_poll_interval_ms)
    state = %{interval: interval, reconcile_opts: Keyword.delete(opts, :name)}
    schedule_poll(interval)
    {:ok, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    {:ok, summary} = reconcile_all(state.reconcile_opts)
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_info(:poll, state) do
    {:ok, _summary} = reconcile_all(state.reconcile_opts)
    schedule_poll(state.interval)
    {:noreply, state}
  end

  defp reconcile_one(reservation, opts) do
    with {:ok, provider_profile} <-
           Cadence.Contacts.fetch_provider_profile_version(
             reservation.organization_id,
             reservation.mission_id,
             reservation.provider_profile_id,
             reservation.provider_profile_version
           ),
         {:ok, client} <- resolve_client(provider_profile, opts),
         {:ok, response} <- fetch_provider_state(client, provider_profile, reservation, opts),
         {:ok, updated} <-
           ProviderReservations.apply_provider_status(
             reservation.organization_id,
             reservation.mission_id,
             reservation.provider_reservation_id,
             response
           ) do
      {:ok, updated}
    else
      {:error, reason} -> record_reconciliation_error(reservation, reason)
    end
  end

  defp fetch_provider_state(client, provider_profile, reservation, opts) do
    call_opts = provider_call_opts(opts)

    case reservation.response_document["id"] || reservation.provider_contact_ref do
      provider_contact_ref when is_binary(provider_contact_ref) and provider_contact_ref != "" ->
        client.describe_contact(provider_profile, provider_contact_ref, call_opts)

      _other ->
        if function_exported?(client, :find_contact_by_idempotency_key, 3) do
          client.find_contact_by_idempotency_key(
            provider_profile,
            reservation.idempotency_key,
            call_opts
          )
        else
          {:error, :provider_idempotency_recovery_unsupported}
        end
    end
  end

  defp record_reconciliation_error(reservation, reason) do
    error_document = %{
      "lifecycle_state" => Atom.to_string(reservation.lifecycle_state),
      "reason" => JsonDocument.encode(reason),
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "provider_reservation_reconciler"
    }

    case ProviderReservations.record_provider_error(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_reservation_id,
           error_document
         ) do
      {:ok, updated} -> {:error, updated, reason}
      {:error, persistence_reason} -> {:error, reservation, {reason, persistence_reason}}
    end
  end

  defp resolve_client(provider_profile, opts) do
    case Keyword.fetch(opts, :client) do
      {:ok, client} -> {:ok, client}
      :error -> Registry.fetch(provider_profile)
    end
  end

  defp provider_call_opts(opts) do
    Keyword.drop(opts, [
      :backoff_ms,
      :client,
      :limit,
      :max_concurrency,
      :mission_id,
      :now,
      :safety_poll_interval_ms
    ])
  end

  defp summarize(results) do
    Enum.reduce(results, %{empty_summary() | results: results}, fn
      {:ok, _reservation}, acc ->
        %{acc | processed: acc.processed + 1, converged: acc.converged + 1}

      {:error, _reservation, _reason}, acc ->
        %{acc | processed: acc.processed + 1, errors: acc.errors + 1}

      {:error, _reason}, acc ->
        %{acc | processed: acc.processed + 1, errors: acc.errors + 1}
    end)
  end

  defp empty_summary, do: %{processed: 0, converged: 0, errors: 0, results: []}

  defp schedule_poll(interval), do: Process.send_after(self(), :poll, interval)
end
