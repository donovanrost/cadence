defmodule Cadence.Runtime.SessionReadiness do
  @moduledoc """
  Root-local, fail-closed uplink admission for shared external resources.

  Provider connections and transport processes register exact incarnations.
  Only a trusted qualification policy can admit recovery or ordinary delivery.
  This is local admission, not external fencing or a durable protocol checkpoint.
  """
  use GenServer
  alias Cadence.Ids
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.{ProcessNamespace, RecoveryExchange, SessionQualification}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  def name(namespace), do: ProcessNamespace.via(namespace, :uplink_session_readiness)

  def register_provider(server, resource, basis),
    do: call(server, {:register_provider, resource, basis})

  def attach(handle, basis), do: call(handle.gate, {:attach, handle, basis})

  def check_recovery(handle, permit, exchange),
    do: call(handle.gate, {:check_recovery, handle, permit, exchange})

  def review(handle), do: call(handle.gate, {:review, handle})
  def begin_recovery(handle, evidence), do: call(handle.gate, {:begin_recovery, handle, evidence})

  def complete_recovery(handle, evidence),
    do: call(handle.gate, {:complete_recovery, handle, evidence})

  def permit_recovery(handle, %RecoveryExchange{} = exchange, evidence),
    do: call(handle.gate, {:permit_recovery, handle, exchange, evidence})

  def admit(handle, generation \\ nil), do: call(handle.gate, {:admit, handle, generation})

  def permit_delivery(handle, admission, digest),
    do: call(handle.gate, {:permit_delivery, handle, admission, digest})

  def finish_admission(handle, permit), do: call(handle.gate, {:finish_admission, handle, permit})
  def check(handle, permit), do: call(handle.gate, {:check, handle, permit})
  def block(handle, reason), do: call(handle.gate, {:block, handle, reason})

  def begin_delivery(handle, permit, recovery_digest),
    do: call(handle.gate, {:begin_delivery, handle, permit, recovery_digest})

  def check_delivery(handle, delivery), do: call(handle.gate, {:check_delivery, handle, delivery})

  def finish_delivery(handle, delivery, outcome),
    do: call(handle.gate, {:finish_delivery, handle, delivery, outcome})

  defp call(server, request) do
    GenServer.call(server, request)
  catch
    :exit, _ -> {:error, :session_gate_unavailable}
  end

  @impl true
  def init(opts),
    do: {:ok, %{policy: Keyword.get(opts, :policy, SessionQualification), resources: %{}}}

  @impl true
  def handle_call({:register_provider, resource, basis}, {pid, _}, state)
      when is_binary(resource) and resource != "" and is_map(basis) do
    prior = state.resources[resource]

    if prior && prior.provider != pid && Process.alive?(prior.provider) do
      next = invalidate(prior, :uplink_resource_conflict)
      {:reply, {:error, :uplink_resource_conflict}, put_session(state, resource, next)}
    else
      session = %{
        provider: pid,
        incarnation: Ids.new("uplink_session"),
        members: %{pid => %{nonce: make_ref(), basis: basis}},
        status: :blocked,
        reason: :fencing_unproven,
        revision: make_ref(),
        basis_generation: Ids.new("uplink_basis"),
        recovery_operations: %{},
        fencing: nil,
        evidence_deadline: nil,
        permits: %{},
        deliveries: %{}
      }

      Process.monitor(pid)
      {:reply, {:ok, handle(resource, session, pid)}, put_session(state, resource, session)}
    end
  end

  def handle_call({:register_provider, _, _}, _from, state),
    do: {:reply, {:error, :uplink_resource_unconfigured}, state}

  def handle_call({:attach, h, basis}, {pid, _}, state) do
    update_session(state, h, fn session ->
      session = invalidate(session, :protocol_recovery_required)
      session = put_in(session.members[pid], %{nonce: make_ref(), basis: basis})
      Process.monitor(pid)
      {{:ok, handle(h.resource, session, pid)}, session}
    end)
  end

  def handle_call({:review, h}, _from, state) do
    update_session(state, h, fn session ->
      {{:ok,
        Map.merge(basis(h.resource, session), %{
          status: session.status,
          reason: session.reason,
          pending_delivery_count: map_size(session.deliveries)
        })}, session}
    end)
  end

  def handle_call({:begin_recovery, h, evidence}, _from, state) do
    update_session(state, h, fn session ->
      with :ok <- no_deliveries(session),
           :ok <- evidence_basis(h.resource, session, evidence),
           :ok <- verify(state.policy, :verify_fencing, [basis(h.resource, session), evidence]) do
        next = %{
          invalidate(session, :protocol_recovery_required)
          | status: :recovering,
            evidence_deadline: evidence_deadline(evidence),
            fencing: evidence
        }

        {:ok, next}
      else
        {:error, reason} -> {{:error, reason}, invalidate(session, reason)}
      end
    end)
  end

  def handle_call({:complete_recovery, h, evidence}, _from, state) do
    update_session(state, h, fn session ->
      with true <- session.status == :recovering,
           :ok <- no_deliveries(session),
           :ok <- evidence_basis(h.resource, session, evidence),
           :ok <-
             verify(state.policy, :verify_protocol_recovery, [
               basis(h.resource, session),
               session.fencing,
               evidence
             ]) do
        {:ok,
         %{
           session
           | status: :ready,
             reason: nil,
             revision: make_ref(),
             permits: %{},
             evidence_deadline: min(session.evidence_deadline, evidence_deadline(evidence))
         }}
      else
        false -> {{:error, :fencing_unproven}, session}
        {:error, reason} -> {{:error, reason}, invalidate(session, reason)}
      end
    end)
  end

  def handle_call({:permit_recovery, h, exchange, evidence}, {pid, _}, state) do
    update_session(state, h, fn session ->
      with true <- session.status == :recovering and h.member == pid and pid != session.provider,
           true <- RecoveryExchange.valid?(exchange),
           :ok <- evidence_basis(h.resource, session, evidence),
           :ok <-
             verify(state.policy, :verify_recovery_exchange, [
               basis(h.resource, session),
               session.fencing,
               RecoveryExchange.basis(exchange),
               evidence
             ]) do
        recovery_grant(session, h, exchange)
      else
        false -> {{:error, :recovery_exchange_not_permitted}, session}
        {:error, reason} -> {{:error, reason}, session}
      end
    end)
  end

  def handle_call({:admit, h, generation}, {pid, _}, state) do
    update_session(state, h, fn session ->
      if session.status == :ready and h.member == pid and pid != session.provider and
           (is_nil(generation) or generation == session.revision),
         do: grant(session, h, :ordinary, nil),
         else: {{:error, {:uplink_session_blocked, session.reason}}, session}
    end)
  end

  def handle_call({:permit_delivery, h, admission, digest}, {pid, _}, state) do
    update_session(state, h, fn session ->
      with true <- pid == h.member,
           :ok <- validate_permit(session, h, admission, :ordinary) do
        grant(session, h, :ordinary_delivery, digest)
      else
        _ -> {{:error, :invalid_session_permit}, session}
      end
    end)
  end

  def handle_call({:finish_admission, h, %{token: token}}, {pid, _}, state) do
    update_session(state, h, fn session ->
      if pid == h.member,
        do: {:ok, %{session | permits: Map.delete(session.permits, token)}},
        else: {{:error, :invalid_session_permit}, session}
    end)
  end

  def handle_call({:check_recovery, h, permit, exchange}, {pid, _}, state) do
    update_session(state, h, fn session ->
      result =
        with true <- pid == h.member and pid != session.provider,
             true <- RecoveryExchange.valid?(exchange),
             {:ok, grant} <- delivery_grant(session, permit, RecoveryExchange.digest(exchange)),
             true <- grant.kind == :recovery and grant.member == h.member,
             do: :ok,
             else: (_ -> {:error, :invalid_session_permit})

      {result, session}
    end)
  end

  def handle_call({:check, h, permit}, _from, state) do
    update_session(state, h, fn session ->
      {validate_permit(session, h, permit, :ordinary), session}
    end)
  end

  def handle_call({:block, h, reason}, _from, state) do
    update_session(state, h, fn session ->
      next = invalidate(session, reason)
      {{:ok, %{pending_delivery_count: map_size(next.deliveries)}}, next}
    end)
  end

  def handle_call({:begin_delivery, h, permit, digest}, {pid, _}, state) do
    update_session(state, h, fn session ->
      with true <- pid == session.provider,
           {:ok, grant} <- delivery_grant(session, permit, digest),
           :ok <- valid_members(session) do
        delivery = make_ref()

        next =
          put_in(session.deliveries[delivery], %{revision: session.revision, member: grant.member})

        next = %{next | permits: Map.delete(next.permits, permit.token)}
        {{:ok, delivery}, next}
      else
        false -> {{:error, :invalid_session_provider}, session}
        {:error, reason} -> {{:error, reason}, session}
      end
    end)
  end

  def handle_call({:check_delivery, h, delivery}, {pid, _}, state) do
    update_session(state, h, fn session ->
      {validate_delivery(session, delivery, pid), session}
    end)
  end

  def handle_call({:finish_delivery, h, delivery, outcome}, {pid, _}, state) do
    update_session(state, h, fn session ->
      result = validate_delivery(session, delivery, pid)
      next = %{session | deliveries: Map.delete(session.deliveries, delivery)}

      if result == :ok and outcome == :ok,
        do: {:ok, next},
        else: {{:error, :send_outcome_unknown}, invalidate(next, :send_outcome_unknown)}
    end)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    resources =
      Enum.reduce(state.resources, %{}, fn {resource, session}, acc ->
        cond do
          session.provider == pid ->
            acc

          Map.has_key?(session.members, pid) ->
            next = %{
              invalidate(session, :session_member_lost)
              | members: Map.delete(session.members, pid)
            }

            Map.put(acc, resource, next)

          true ->
            Map.put(acc, resource, session)
        end
      end)

    {:noreply, %{state | resources: resources}}
  end

  defp update_session(state, h, fun) do
    state = reap_members(state, h.resource)

    with %{incarnation: incarnation} = session <- state.resources[h.resource],
         true <- incarnation == h.incarnation,
         %{nonce: nonce} <- session.members[h.member],
         true <- nonce == h.nonce,
         :ok <- valid_members(session) do
      {reply, next} = fun.(expire(session))
      {:reply, reply, put_session(state, h.resource, next)}
    else
      _ -> {:reply, {:error, :stale_uplink_session}, state}
    end
  end

  defp reap_members(state, resource) do
    case state.resources[resource] do
      nil ->
        state

      session ->
        alive = Map.reject(session.members, fn {pid, _} -> not Process.alive?(pid) end)

        if map_size(alive) == map_size(session.members),
          do: state,
          else:
            put_session(state, resource, %{
              invalidate(session, :session_member_lost)
              | members: alive
            })
    end
  end

  defp put_session(state, resource, session), do: put_in(state.resources[resource], session)

  defp invalidate(session, reason),
    do: %{
      session
      | status: :blocked,
        reason: reason,
        revision: make_ref(),
        basis_generation: Ids.new("uplink_basis"),
        recovery_operations: %{},
        permits: %{},
        fencing: nil,
        evidence_deadline: nil
    }

  defp handle(resource, session, pid),
    do: %{
      gate: self(),
      resource: resource,
      incarnation: session.incarnation,
      member: pid,
      nonce: session.members[pid].nonce
    }

  defp basis(resource, session) do
    immutable = %{
      resource_id: resource,
      incarnation: session.incarnation,
      generation: session.basis_generation,
      provider: session.members[session.provider].basis,
      transports:
        session.members
        |> Map.delete(session.provider)
        |> Map.values()
        |> Enum.map(& &1.basis)
        |> Enum.sort()
    }

    Map.put(immutable, :basis_sha256, ContentHash.term_sha256(immutable))
  end

  defp evidence_basis(resource, session, evidence) when is_map(evidence) do
    if evidence[:basis_sha256] == basis(resource, session).basis_sha256 and
         is_binary(evidence[:reference]) and evidence[:reference] != "" and
         byte_size(:erlang.term_to_binary(evidence)) <= 65_536 and valid_until?(evidence),
       do: :ok,
       else: {:error, :session_evidence_basis_changed}
  end

  defp evidence_basis(_, _, _), do: {:error, :invalid_session_evidence}

  defp valid_until?(%{valid_until: %DateTime{} = until}) do
    remaining = DateTime.diff(until, DateTime.utc_now(), :millisecond)
    remaining > 0 and remaining <= 300_000
  end

  defp valid_until?(_), do: false

  defp evidence_deadline(evidence),
    do:
      System.monotonic_time(:millisecond) +
        DateTime.diff(evidence.valid_until, DateTime.utc_now(), :millisecond)

  defp expire(%{evidence_deadline: deadline, status: status} = session)
       when is_integer(deadline) and status in [:ready, :recovering] do
    if deadline <= System.monotonic_time(:millisecond),
      do: invalidate(session, :session_evidence_expired),
      else: session
  end

  defp expire(session), do: session

  defp no_deliveries(%{deliveries: deliveries}) when map_size(deliveries) == 0, do: :ok
  defp no_deliveries(_), do: {:error, :session_delivery_in_flight}

  defp valid_members(session) do
    if Enum.all?(Map.keys(session.members), &Process.alive?/1) and
         Process.alive?(session.provider), do: :ok, else: {:error, :session_member_lost}
  end

  defp verify(policy, callback, args) do
    case apply(policy, callback, args) do
      :ok -> :ok
      {:error, _} = error -> error
      _ -> {:error, :session_qualification_failed}
    end
  rescue
    _ -> {:error, :session_qualification_failed}
  catch
    _, _ -> {:error, :session_qualification_failed}
  end

  defp grant(session, h, kind, digest) do
    token = make_ref()
    permit = %{token: token, incarnation: h.incarnation, generation: session.revision}

    grant = %{
      revision: session.revision,
      member: h.member,
      kind: kind,
      digest: digest,
      expires: System.monotonic_time(:millisecond) + 30_000
    }

    # Admission tokens are short-lived and bounded; never accumulate one per command forever.
    now = System.monotonic_time(:millisecond)
    permits = Map.reject(session.permits, fn {_, p} -> p.expires < now end)

    if map_size(permits) < 1024,
      do: {{:ok, permit}, %{session | permits: Map.put(permits, token, grant)}},
      else: {{:error, :session_admission_full}, %{session | permits: permits}}
  end

  defp recovery_grant(session, h, exchange) do
    digest = RecoveryExchange.digest(exchange)

    case session.recovery_operations[exchange.operation_id] do
      nil ->
        if map_size(session.recovery_operations) < 1024,
          do: new_recovery_grant(session, h, exchange.operation_id, digest),
          else: {{:error, :session_admission_full}, session}

      {^digest, permit} ->
        case delivery_grant(session, permit, digest) do
          {:ok, _} -> {{:ok, permit}, session}
          _ -> {{:error, :recovery_exchange_already_used}, session}
        end

      _ ->
        {{:error, :recovery_operation_conflict}, session}
    end
  end

  defp new_recovery_grant(session, h, operation_id, digest) do
    case grant(session, h, :recovery, digest) do
      {{:ok, permit}, next} ->
        {{:ok, permit}, put_in(next.recovery_operations[operation_id], {digest, permit})}

      result ->
        result
    end
  end

  defp validate_permit(session, h, permit, kind) do
    with {:ok, grant} <- delivery_grant(session, permit, nil),
         true <- grant.member == h.member and grant.kind == kind do
      :ok
    else
      _ -> {:error, :invalid_session_permit}
    end
  end

  defp delivery_grant(session, %{token: token}, digest) do
    with %{revision: revision, expires: expiry} = grant <- session.permits[token],
         true <- revision == session.revision and expiry >= System.monotonic_time(:millisecond),
         true <- permitted_kind?(grant, session.status, digest),
         true <- Process.alive?(grant.member) do
      {:ok, grant}
    else
      _ -> {:error, :invalid_session_permit}
    end
  end

  defp delivery_grant(_, _, _), do: {:error, :invalid_session_permit}

  defp permitted_kind?(%{kind: :ordinary}, :ready, nil), do: true
  defp permitted_kind?(%{kind: :ordinary_delivery, digest: digest}, :ready, digest), do: true
  defp permitted_kind?(%{kind: :recovery, digest: digest}, :recovering, digest), do: true
  defp permitted_kind?(_, _, _), do: false

  defp validate_delivery(session, delivery, pid) do
    with true <- pid == session.provider,
         %{revision: revision} <- session.deliveries[delivery],
         true <- revision == session.revision,
         :ok <- valid_members(session) do
      :ok
    else
      _ -> {:error, :invalid_session_delivery}
    end
  end
end
