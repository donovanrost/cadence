defmodule Cadence.Runtime.Protocol.Supervisor do
  @moduledoc """
  Dynamic supervisor for protocol ChannelService processes.

  Protocol state is keyed by {mission_id, ChannelId} and survives interface churn.
  """

  use DynamicSupervisor

  require Logger

  alias Cadence.CCSDS.PDUDispatcher
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Protocol.ChannelService
  alias Cadence.Runtime.Transport.COP1.FOP

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    DynamicSupervisor.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @impl true
  def init(mission_id) do
    Logger.debug("Starting Protocol.Supervisor for mission_id=#{mission_id}")
    Process.put(:mission_id, mission_id)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def terminate(reason, _state) do
    case Process.get(:mission_id) do
      nil ->
        :ok

      mission_id ->
        Logger.debug(
          "Stopping Protocol.Supervisor for mission_id=#{mission_id} reason=#{inspect(reason)}"
        )
    end

    :ok
  end

  @spec ensure_channel(String.t(), ChannelId.t()) :: :ok
  def ensure_channel(mission_id, %ChannelId{} = channel_id) do
    case lookup_channel(mission_id, channel_id) do
      {:ok, _pid} ->
        :ok

      :error ->
        child_spec = {ChannelService, mission_id: mission_id, channel_id: channel_id}

        case DynamicSupervisor.start_child(via_tuple(mission_id), child_spec) do
          {:ok, _pid} ->
            Logger.debug("protocol.channel_service.started",
              mission_id: mission_id,
              channel_id: ChannelId.key(channel_id)
            )

            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "protocol.channel_service.start_failed reason=#{inspect(reason)}",
              mission_id: mission_id,
              channel_id: ChannelId.key(channel_id)
            )

            :ok
        end
    end
  end

  @spec ensure_pdu_dispatcher(String.t(), ChannelId.t(), map()) :: :ok
  def ensure_pdu_dispatcher(mission_id, %ChannelId{} = channel_id, protocol_config)
      when is_map(protocol_config) do
    child_spec =
      {PDUDispatcher,
       mission_id: mission_id, channel_id: channel_id, protocol_config: protocol_config}

    case DynamicSupervisor.start_child(via_tuple(mission_id), child_spec) do
      {:ok, _pid} ->
        Logger.debug("protocol.pdu_dispatcher.started",
          mission_id: mission_id,
          channel_id: ChannelId.key(channel_id)
        )

        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.warning("protocol.pdu_dispatcher.start_failed",
          mission_id: mission_id,
          channel_id: ChannelId.key(channel_id),
          reason: inspect(reason)
        )

        :ok
    end
  end

  @spec ensure_cop1_fop(String.t(), ChannelId.t(), map()) :: :ok
  def ensure_cop1_fop(mission_id, %ChannelId{} = channel_id, protocol_config)
      when is_map(protocol_config) do
    child_spec =
      {FOP, mission_id: mission_id, channel_id: channel_id, protocol_config: protocol_config}

    case DynamicSupervisor.start_child(via_tuple(mission_id), child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @spec lookup_channel(String.t(), ChannelId.t()) :: {:ok, pid()} | :error
  def lookup_channel(mission_id, %ChannelId{} = channel_id) do
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:channel_service, mission_id, ChannelId.key(channel_id)}
         ) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:protocol_supervisor, mission_id}}}
  end
end
