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
  alias Cadence.Control.UplinkReadiness
  alias Cadence.Runtime.{ProcessNamespace, UplinkSessions}

  @tick_ms 15_000
  @requalify_after_ms 180_000
  @clcw_bound_ms 15_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

  @doc "Runs one pass now (tests and operators)."
  @spec qualify_now(GenServer.server()) :: map()
  def qualify_now(server \\ __MODULE__), do: GenServer.call(server, :qualify_now, 60_000)

  @doc "Re-qualifies one session now, whether or not it's due (Recover uplink, #58)."
  @spec requalify(GenServer.server(), tuple()) :: :ready | {:error, term()}
  def requalify(server \\ __MODULE__, key), do: GenServer.call(server, {:requalify, key}, 60_000)

  @impl true
  def init(opts) do
    state = %{
      namespace: Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0),
      tick_ms: Keyword.get(opts, :tick_ms, @tick_ms),
      readiness:
        UplinkReadiness.create_table(Keyword.get(opts, :readiness_table, UplinkReadiness.table())),
      qualified: %{},
      # The provider booking of a session's contact (injectable for tests).
      booking: Keyword.get(opts, :booking, &Booking.for_session/1)
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:qualify_now, _from, state) do
    {results, state} = run(state)
    {:reply, results, state}
  end

  def handle_call({:requalify, key}, _from, state) do
    case Enum.find(UplinkSessions.list(state.namespace), &(elem(&1, 0) == key)) do
      nil ->
        {:reply, {:error, :uplink_session_not_running}, state}

      {key, pid} ->
        {result, _booking} =
          qualified = qualify(pid, %{}, System.monotonic_time(:millisecond), state.booking)

        {_view, state} = observe(state, key, pid, qualified, System.monotonic_time(:millisecond))

        reply =
          case result do
            {:qualified, _incarnation} -> :ready
            {:kept, _incarnation} -> :ready
            {:skipped, reason} -> {:error, reason}
            {:error, reason} -> {:error, reason}
          end

        {:reply, reply, state}
    end
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
    sessions = UplinkSessions.list(state.namespace)

    {results, state} =
      Enum.reduce(sessions, {%{}, %{state | qualified: %{}}}, fn {key, pid}, {results, acc} ->
        result = qualify(pid, state.qualified, now, state.booking)

        {view, acc} =
          observe(
            %{acc | qualified: Map.merge(state.qualified, acc.qualified)},
            key,
            pid,
            result,
            now
          )

        {Map.put(results, key, view), acc}
      end)

    live = MapSet.new(sessions, &elem(&1, 0))

    state.readiness
    |> UplinkReadiness.keys()
    |> MapSet.difference(live)
    |> Enum.each(&UplinkReadiness.forget(state.readiness, &1, DateTime.utc_now()))

    {results, state}
  end

  # Records the session's readiness (#58) and keeps the qualified-at memory.
  defp observe(state, key, pid, {result, booking}, now) do
    {view, qualified} =
      case result do
        {:qualified, incarnation} ->
          {:qualified, Map.put(state.qualified, incarnation, now)}

        {:kept, incarnation} ->
          {:ready, Map.put(state.qualified, incarnation, state.qualified[incarnation] || now)}

        {:skipped, _reason} = skipped ->
          {skipped, state.qualified}

        {:error, reason} ->
          Logger.warning("uplink session #{inspect(key)} not qualified: #{inspect(reason)}")
          {{:error, reason}, state.qualified}
      end

    record_readiness(state.readiness, key, pid, booking, result)
    {view, %{state | qualified: qualified}}
  end

  # Recorded from the booking found before the challenge, so a session the challenge leaves
  # unreviewable (a failed recovery) still reads blocked with its reason (#38 positive test).
  defp record_readiness(_table, key, _pid, nil, {:error, reason}) do
    Logger.warning(
      "uplink session #{inspect(key)} readiness not recorded (no provider booking): " <>
        inspect(reason)
    )
  end

  # Not a provider-booked uplink: not this read's.
  defp record_readiness(_table, _key, _pid, nil, _result), do: :ok

  defp record_readiness(table, key, pid, booking, result) do
    {readiness, reason} = readiness(result, pid)
    UplinkReadiness.record(table, key, pass(booking), readiness, reason, DateTime.utc_now())
  end

  # Ready only on a positive answer: a runtime that can't report its protocol state isn't (#38).
  # #38, #59 follow-up: a qualified session is ready only while its CLCW stream is live. A
  # spacecraft reports continuously, so no first report within the bound blocks the pass with a
  # reason, and a report older than the bound reads qualifying, never ready.
  defp readiness(result, pid) when elem(result, 0) in [:qualified, :kept] do
    case UplinkSessions.clcw_report(pid) do
      {:received, age} when age > @clcw_bound_ms -> {:qualifying, :cop1_clcw_stale}
      {:received, _age} -> {:ready, nil}
      {:awaiting, waited} when waited > @clcw_bound_ms -> {:blocked, :cop1_no_clcw_report}
      {:awaiting, _waited} -> {:qualifying, :cop1_awaiting_clcw}
      :unavailable -> {:qualifying, :uplink_state_unavailable}
    end
  end

  defp readiness({:skipped, reason}, _pid), do: {:qualifying, reason_key(reason)}
  defp readiness({:error, reason}, _pid), do: {:blocked, reason_key(reason)}

  @doc false
  # Recorded readiness reasons are keys (§8 domain 9; api-ops' reason_key, normalized at the
  # source): an atom as is, a provider error as provider_<category>, {reason, detail} as its
  # reason, anything else unknown. The detail stays in this driver's log line.
  def reason_key(reason) when is_atom(reason) or is_binary(reason), do: reason

  def reason_key(%{category: category}) when is_atom(category) and not is_nil(category),
    do: String.to_atom("provider_" <> Atom.to_string(category))

  def reason_key({reason, _detail}) when is_atom(reason), do: reason
  def reason_key(_other), do: :unknown

  defp pass(booking) do
    Map.take(booking, [
      :organization_id,
      :mission_id,
      :scheduled_contact_id,
      :provider_reservation_id,
      :provider_contact_ref,
      :provider_id,
      :spacecraft_id,
      :ground_station_ref,
      :starts_at,
      :ends_at
    ])
  end

  # `{result, booking | nil}`: the booking is kept even when the challenge fails.
  defp qualify(pid, qualified, now, lookup) do
    with {:ok, review} <- review(pid),
         :ok <- provider_managed(review),
         {:ok, booking} <- booking(lookup, review.provider) do
      {challenge(pid, review, booking, qualified, now), booking}
    else
      other -> {other, nil}
    end
  catch
    :exit, reason -> {{:error, {:transport_runtime_unavailable, reason}}, nil}
  end

  # DECISIONS #67: a peer the provider didn't attest holds the connection (a stray took the
  # listener first). Drop it so the attested peer can connect; it reads blocked meanwhile.
  defp challenge(pid, review, booking, qualified, now) do
    case challenge_session(pid, review, booking, qualified, now) do
      {:error, :attestation_peer_mismatch} ->
        drop_unverified_peer(pid, review.provider.peer)
        {:error, :unverified_peer_connected}

      result ->
        result
    end
  end

  defp drop_unverified_peer(pid, peer) do
    _ = UplinkSessions.drop_unverified_peer(pid, peer, :attestation_peer_mismatch)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp challenge_session(pid, review, booking, qualified, now) do
    with :ok <- due(review, qualified, now),
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
  defp booking(lookup, provider_basis) do
    case lookup.(provider_basis) do
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
