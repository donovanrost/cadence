defmodule Cadence.Runtime.Transport do
  @moduledoc """
  Transport access for sending bytes via an active transport process.
  """

  @registry Cadence.MissionRegistry

  @spec send_bytes(String.t(), String.t(), binary(), map()) :: :ok | {:error, term()}
  def send_bytes(mission_id, transport_id, bytes, _meta \\ %{}) when is_binary(bytes) do
    case Registry.lookup(@registry, {:transport, mission_id, transport_id}) do
      [{pid, _}] ->
        GenServer.cast(pid, {:send, bytes, %{}})
        :ok

      [] ->
        {:error, :transport_not_found}
    end
  end

  @spec connected?(String.t(), String.t()) :: boolean()
  def connected?(mission_id, transport_id) do
    case Registry.lookup(@registry, {:transport, mission_id, transport_id}) do
      [{pid, _}] ->
        GenServer.call(pid, :connected?)

      [] ->
        false
    end
  end
end
