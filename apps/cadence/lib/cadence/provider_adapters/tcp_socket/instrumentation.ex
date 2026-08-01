defmodule Cadence.ProviderAdapters.TCPSocket.Instrumentation do
  @moduledoc false

  @receive_event [:cadence, :provider_adapters, :tcp_socket, :receive]

  @spec receive_event() :: [atom()]
  def receive_event, do: @receive_event

  @spec record_receive(map(), binary(), non_neg_integer()) :: :ok
  def record_receive(state, data, duration_us)
      when is_map(state) and is_binary(data) and is_integer(duration_us) and duration_us >= 0 do
    :telemetry.execute(
      @receive_event,
      %{byte_count: byte_size(data), duration_us: duration_us},
      %{
        direction: state.direction,
        protocol_family: state.ingress_protocol_family
      }
    )
  end
end
