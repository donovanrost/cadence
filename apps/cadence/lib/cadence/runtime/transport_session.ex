defmodule Cadence.Runtime.TransportSession do
  @moduledoc false
  alias Cadence.ActionRequests.ProviderRequest
  alias Cadence.Platform.ContentHash
  alias Cadence.ProviderAdapters
  alias Cadence.Runtime.{RecoveryExchange, SessionReadiness, TimerService, TransportRecords}

  def ensure(%{session_handle: nil} = state) do
    case provider(state.configuration) do
      nil ->
        {:ok, state}

      {binding, adapter} ->
        with {:ok, handle} <-
               ProviderAdapters.uplink_session(
                 state.process_namespace,
                 state.mission_id,
                 state.realized_contact_id,
                 state.path_id,
                 binding,
                 adapter
               ),
             {:ok, attached} <-
               SessionReadiness.attach(handle, %{
                 mission_id: state.mission_id,
                 contact_id: state.realized_contact_id,
                 path_id: state.path_id,
                 binding_id: state.capability_instance_id,
                 family_key: state.family_key,
                 configuration_sha256: ContentHash.term_sha256(state.configuration)
               }) do
          {:ok, %{state | session_handle: attached}}
        end
    end
  catch
    :exit, _ -> {:error, :session_gate_unavailable}
  end

  def ensure(state), do: {:ok, state}

  def admit(%{protocol_restoration: restoration}) when not is_nil(restoration),
    do: {:error, :protocol_recovery_unqualified}

  def admit(state) do
    with {:ok, state} <- ensure(state),
         {:ok, permit} <- admission(state) do
      {:ok, permit, state}
    end
  end

  defp admission(%{session_handle: nil}), do: {:ok, nil}
  defp admission(state), do: SessionReadiness.admit(state.session_handle, state.uplink_generation)

  def input(state, nil) do
    if is_nil(provider(state.configuration)),
      do: {:ok, state},
      else: {:error, :invalid_session_permit}
  end

  def input(%{session_handle: nil}, _permit), do: {:error, :invalid_session_permit}

  def input(state, %{generation: generation} = permit) do
    with true <- is_nil(state.uplink_generation) or state.uplink_generation == generation,
         :ok <- SessionReadiness.check(state.session_handle, permit) do
      {:ok, %{state | session_admission: permit, uplink_generation: permit.generation}}
    else
      _ -> {:error, :invalid_session_permit}
    end
  end

  def input(_state, _permit), do: {:error, :invalid_session_permit}

  def authorize_actions(state, actions) do
    if Enum.any?(actions, &match?(%ProviderRequest{}, &1)) do
      admission_for_actions(state)
    else
      {:ok, nil}
    end
  end

  defp admission_for_actions(%{session_handle: nil}), do: {:error, :uplink_session_unavailable}
  defp admission_for_actions(%{session_admission: nil} = state), do: admission(state)

  defp admission_for_actions(state) do
    with :ok <- SessionReadiness.check(state.session_handle, state.session_admission),
         do: {:ok, state.session_admission}
  end

  def deliver(state, %ProviderRequest{} = request, admission) do
    with :ok <- matching_provider(state, request),
         {:ok, permit} <-
           SessionReadiness.permit_delivery(
             state.session_handle,
             admission,
             ProviderRequest.digest(request)
           ) do
      ProviderAdapters.deliver_uplink(
        state.process_namespace,
        state.mission_id,
        state.realized_contact_id,
        state.path_id,
        %{request | session_permit: permit}
      )
    end
  end

  def finish_admission(%{session_handle: nil}, _), do: :ok
  def finish_admission(_state, nil), do: :ok

  def finish_admission(state, %{token: _} = permit),
    do: SessionReadiness.finish_admission(state.session_handle, permit)

  def finish_admission(_state, _permit), do: :ok

  def action(state, operation, args) do
    with {:ok, state} <- ensure(state),
         true <- not is_nil(state.session_handle) do
      run_action(state, operation, args)
    else
      false -> {{:error, :uplink_session_unavailable}, state}
      {:error, _} = error -> {error, state}
    end
  end

  defp run_action(state, :review, []) do
    result =
      with {:ok, review} <- SessionReadiness.review(state.session_handle),
           {:ok, sends} <- TransportRecords.review(review.resource_id),
           do: {:ok, Map.put(review, :transport_sends, sends)}

    {result, state}
  end

  defp run_action(state, :begin_recovery, [evidence]) do
    {SessionReadiness.begin_recovery(state.session_handle, evidence), cancel_timers(state)}
  end

  defp run_action(state, :permit_recovery, [exchange, evidence]),
    do: {SessionReadiness.permit_recovery(state.session_handle, exchange, evidence), state}

  defp run_action(state, :block, [reason]) do
    {SessionReadiness.block(state.session_handle, reason), cancel_timers(state)}
  end

  defp run_action(%{protocol_restoration: restoration} = state, :complete_recovery, _args)
       when not is_nil(restoration), do: {{:error, :protocol_recovery_unqualified}, state}

  defp run_action(state, :complete_recovery, [evidence]) do
    with :ok <- TransportRecords.clear?(state.session_handle.resource, state.send_runtime_id),
         :ok <- SessionReadiness.complete_recovery(state.session_handle, evidence),
         {:ok, permit} <- SessionReadiness.admit(state.session_handle) do
      {:ok, %{cancel_timers(state) | uplink_generation: permit.generation}}
    else
      error -> {error, state}
    end
  end

  defp run_action(state, :exchange, [%RecoveryExchange{} = exchange, permit]) do
    request =
      ProviderRequest.new(%{
        provider_binding_id: exchange.provider_binding_id,
        provider_adapter_key: exchange.provider_adapter_key,
        payloads_base64: exchange.payloads_base64,
        payload_count: length(exchange.payloads_base64),
        recovery_exchange: exchange,
        session_permit: permit
      })

    result =
      with :ok <- matching_provider(state, request),
           :ok <- SessionReadiness.check_recovery(state.session_handle, permit, exchange),
           {:ok, [request]} <- TransportRecords.prepare(state, [request], state.extension_state) do
        deliver_recovery(state, request)
      end

    {result, state}
  end

  defp deliver_recovery(state, request) do
    result =
      with {:ok, metadata} <-
             ProviderAdapters.deliver_uplink(
               state.process_namespace,
               state.mission_id,
               state.realized_contact_id,
               state.path_id,
               request
             ),
           :ok <- TransportRecords.confirm([request]),
           do: {:ok, metadata}

    if match?({:error, _}, result),
      do: SessionReadiness.block(state.session_handle, :send_outcome_unknown)

    result
  end

  defp cancel_timers(state),
    do: %{
      state
      | timer_service: TimerService.cancel_all(state.timer_service),
        session_admission: nil
    }

  defp matching_provider(state, request) do
    if provider(state.configuration) ==
         {request.provider_binding_id, request.provider_adapter_key},
       do: :ok,
       else: {:error, :uplink_provider_mismatch}
  end

  defp provider(configuration) when is_map(configuration) do
    binding = Map.get(configuration, :provider_binding_id, configuration["provider_binding_id"])
    adapter = Map.get(configuration, :provider_adapter_key, configuration["provider_adapter_key"])
    adapter = if adapter == "tcp_socket", do: :tcp_socket, else: adapter
    if is_binary(binding) and is_atom(adapter), do: {binding, adapter}, else: nil
  end

  defp provider(_), do: nil
end
