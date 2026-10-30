defmodule Cadence.ProviderAdapters.TCPSocket.Session do
  @moduledoc false
  alias Cadence.ActionRequests.ProviderRequest
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.{ProcessNamespace, RecoveryExchange, SessionReadiness}

  def initialize(state, opts) do
    config = Keyword.fetch!(opts, :configuration)
    namespace = Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    Map.merge(state, %{
      session_gate: SessionReadiness.name(namespace),
      session_resource: Map.get(config, :uplink_resource_id, config["uplink_resource_id"]),
      session_configuration_sha256: ContentHash.term_sha256(config),
      session_handle: nil,
      session_blocking_reason: :tcp_provider_not_connected
    })
  end

  def connected(state) do
    block(state, :connection_replaced)

    basis = %{
      adapter_key: :tcp_socket,
      mission_id: state.mission_id,
      contact_id: state.realized_contact_id,
      path_id: state.path_id,
      binding_id: state.provider_binding_id,
      configuration_sha256: state.session_configuration_sha256
    }

    case SessionReadiness.register_provider(state.session_gate, state.session_resource, basis) do
      {:ok, handle} ->
        %{state | session_handle: handle, session_blocking_reason: :fencing_unproven}

      {:error, reason} ->
        %{state | session_handle: nil, session_blocking_reason: reason}
    end
  end

  def block(%{session_handle: nil} = state, reason),
    do: %{state | session_blocking_reason: reason}

  def block(state, reason) do
    SessionReadiness.block(state.session_handle, reason)
    %{state | session_blocking_reason: reason}
  end

  def handle(%{session_handle: nil, session_blocking_reason: reason}), do: {:error, reason}
  def handle(state), do: {:ok, state.session_handle}

  def snapshot(%{session_handle: nil} = state),
    do: %{status: :blocked, reason: state.session_blocking_reason}

  def snapshot(state) do
    case SessionReadiness.review(state.session_handle) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> %{status: :blocked, reason: reason}
    end
  end

  def begin_delivery(%{session_handle: nil} = state, _request),
    do: {:error, {:uplink_session_blocked, state.session_blocking_reason}}

  def begin_delivery(state, %ProviderRequest{} = request) do
    with true <-
           request.provider_binding_id == state.provider_binding_id and
             request.provider_adapter_key == :tcp_socket,
         {:ok, digest} <- request_digest(request) do
      SessionReadiness.begin_delivery(state.session_handle, request.session_permit, digest)
    else
      _ -> {:error, :invalid_session_delivery}
    end
  end

  def check(state, delivery), do: SessionReadiness.check_delivery(state.session_handle, delivery)

  def finish(state, delivery, result),
    do: SessionReadiness.finish_delivery(state.session_handle, delivery, result)

  defp request_digest(%ProviderRequest{recovery_exchange: nil} = request),
    do: {:ok, ProviderRequest.digest(request)}

  defp request_digest(
         %ProviderRequest{recovery_exchange: %RecoveryExchange{} = exchange} = request
       ) do
    if RecoveryExchange.valid?(exchange) and
         request.provider_binding_id == exchange.provider_binding_id and
         request.provider_adapter_key == exchange.provider_adapter_key and
         request.payloads_base64 == exchange.payloads_base64 and
         is_nil(request.command_release_attempt_id) and is_nil(request.command_request_id),
       do: {:ok, RecoveryExchange.digest(exchange)},
       else: {:error, :invalid_recovery_exchange}
  end

  defp request_digest(_), do: {:error, :invalid_recovery_exchange}
end
