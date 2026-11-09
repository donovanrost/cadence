defmodule Cadence.Control.UplinkQualification do
  @moduledoc """
  Drives qualification of provider-managed uplink sessions (#44 D2).

  Every tick it reviews the running transport runtimes. A provider-booked uplink session that
  isn't ready, or whose evidence is about to lapse, is challenged: the driver asks the booking's
  provider for a `fencing` attestation over the session's current basis hash and begins recovery
  with it, then asks for a `protocol` attestation and completes recovery. The configured
  `Cadence.Control.UplinkSessionQualification` decides; this process only fetches evidence.
  Sessions with deliveries in flight are left alone until their evidence lapses.
  """

  use GenServer

  require Logger

  alias Cadence.Control.UplinkQualification.Booking
  alias Cadence.Runtime.{ProcessNamespace, UplinkSessions}

  @tick_ms 15_000
  @requalify_after_ms 180_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Runs one pass now (tests and operators)."
  @spec qualify_now(GenServer.server()) :: map()
  def qualify_now(server \\ __MODULE__), do: GenServer.call(server, :qualify_now, 60_000)

  @impl true
  def init(opts) do
    state = %{
      namespace: Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0),
      tick_ms: Keyword.get(opts, :tick_ms, @tick_ms),
      qualified: %{}
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:qualify_now, _from, state) do
    {results, state} = run(state)
    {:reply, results, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_results, state} = run(state)
    schedule(state)
    {:noreply, state}
  end

  defp schedule(%{tick_ms: ms}) when is_integer(ms) and ms > 0,
    do: Process.send_after(self(), :tick, ms)

  defp schedule(_state), do: :ok

  defp run(state) do
    now = System.monotonic_time(:millisecond)

    {results, qualified} =
      state.namespace
      |> UplinkSessions.list()
      |> Enum.reduce({%{}, %{}}, fn {key, pid}, {results, qualified} ->
        case qualify(pid, state.qualified, now) do
          {:qualified, incarnation} ->
            {Map.put(results, key, :qualified), Map.put(qualified, incarnation, now)}

          {:kept, incarnation} ->
            {Map.put(results, key, :ready),
             Map.put(qualified, incarnation, state.qualified[incarnation])}

          {:skipped, _reason} = skipped ->
            {Map.put(results, key, skipped), qualified}

          {:error, reason} ->
            Logger.warning("uplink session #{inspect(key)} not qualified: #{inspect(reason)}")
            {Map.put(results, key, {:error, reason}), qualified}
        end
      end)

    {results, %{state | qualified: qualified}}
  end

  defp qualify(pid, qualified, now) do
    with {:ok, review} <- review(pid),
         :ok <- provider_managed(review),
         :ok <- due(review, qualified, now),
         {:ok, booking} <- booking(review.provider),
         {:ok, fencing} <- evidence(booking, review, "fencing"),
         :ok <- UplinkSessions.begin_recovery(pid, fencing),
         {:ok, review} <- review(pid),
         {:ok, protocol} <- evidence(booking, review, "protocol"),
         :ok <- UplinkSessions.complete_recovery(pid, protocol) do
      {:qualified, review.incarnation}
    end
  catch
    :exit, reason -> {:error, {:transport_runtime_unavailable, reason}}
  end

  defp review(pid) do
    case UplinkSessions.review(pid) do
      {:ok, review} -> {:ok, review}
      {:error, reason} -> {:skipped, reason}
    end
  end

  defp provider_managed(%{provider: %{adapter_key: :tcp_socket, peer: peer}})
       when is_binary(peer),
       do: :ok

  defp provider_managed(_review), do: {:skipped, :not_a_provider_uplink}

  defp due(%{status: :ready, pending_delivery_count: pending} = review, qualified, now) do
    case qualified[review.incarnation] do
      at when is_integer(at) and now - at < @requalify_after_ms -> {:kept, review.incarnation}
      _at when pending > 0 -> {:kept, review.incarnation}
      _stale -> :ok
    end
  end

  defp due(_review, _qualified, _now), do: :ok

  # Sessions that no provider booked (hand-built contacts, tests) aren't this driver's to qualify.
  defp booking(provider_basis) do
    case Booking.for_session(provider_basis) do
      {:ok, booking} -> {:ok, booking}
      {:error, reason} -> {:skipped, reason}
    end
  end

  defp can_attest(client) do
    if Code.ensure_loaded?(client) and function_exported?(client, :attest_uplink_session, 4),
      do: :ok,
      else: {:error, :provider_cannot_attest_uplink_sessions}
  end

  defp evidence(booking, review, purpose) do
    attrs = %{"challenge" => review.basis_sha256, "purpose" => purpose}

    with :ok <- can_attest(booking.client),
         {:ok, attestation} <-
           booking.client.attest_uplink_session(
             booking.context,
             booking.provider_contact_ref,
             attrs,
             booking.call_opts
           ),
         {:ok, valid_until, _offset} <- DateTime.from_iso8601(attestation["valid_until"] || "") do
      {:ok,
       %{
         basis_sha256: review.basis_sha256,
         reference: "provider-attestation:#{purpose}:#{booking.provider_contact_ref}",
         valid_until: valid_until,
         attestation: attestation
       }}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :malformed_provider_attestation}
    end
  end
end
