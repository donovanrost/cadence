defmodule Cadence.Runtime.Uplink.Dispatcher do
  @moduledoc """
  Mission-scoped uplink dispatcher.

  Resolves a target to a ChannelId, encodes the PDU, and forwards bytes to the
  ChannelService. Link selection is handled by the LinkController.
  """

  use GenServer

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Links.TargetDirectory
  alias Cadence.Runtime.Protocol.ChannelService
  alias Cadence.Runtime.Transport
  alias Cadence.Runtime.Transport.COP1.Config, as: COP1Config
  alias Cadence.Runtime.Uplink.RouteDecision
  alias Cadence.Runtime.Uplink.UplinkPDU
  alias Cadence.Transport.TCStreamId

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.mission_id))
  end

  @spec dispatch_pdu(String.t(), UplinkPDU.t(), keyword()) ::
          {:ok, RouteDecision.t()} | {:error, term()} | {:defer, term()}
  def dispatch_pdu(mission_id, %UplinkPDU{} = uplink_pdu, opts \\ []) do
    GenServer.call(via_tuple(mission_id), {:dispatch_pdu, uplink_pdu, opts})
  end

  @spec connected?(String.t(), String.t()) :: boolean()
  def connected?(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id), {:connected?, target_id})
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:uplink_dispatcher, mission_id}}}
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%MissionConfig{} = config) do
    {:ok, %State{mission_id: config.mission_id}}
  end

  @impl true
  def handle_call({:connected?, target_id}, _from, state) do
    connected =
      state.mission_id
      |> TargetDirectory.list_channels(target_id)
      |> Enum.any?(fn channel_id ->
        case active_interface_for_channel(state.mission_id, channel_id) do
          nil -> false
          interface_id -> Transport.connected?(state.mission_id, interface_id)
        end
      end)

    {:reply, connected, state}
  end

  @impl true
  def handle_call({:dispatch_pdu, uplink_pdu, opts}, _from, state) do
    case resolve_channel(state.mission_id, uplink_pdu.target_id, opts) do
      {:ok, channel_id} ->
        do_dispatch(state, channel_id, uplink_pdu, opts)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_dispatch(state, %ChannelId{} = channel_id, %UplinkPDU{} = uplink_pdu, opts) do
    with {:ok, interface_id} <- select_interface(state.mission_id, channel_id, opts),
         :ok <-
           ChannelService.send_uplink(state.mission_id, channel_id, uplink_pdu.pdu, %{
             interface_id: interface_id,
             cop1_context: Keyword.get(opts, :cop1_context)
           }) do
      decision = %RouteDecision{
        target_id: uplink_pdu.target_id,
        pdu_type: uplink_pdu.pdu_type,
        apid: uplink_pdu.apid,
        interface_id: interface_id,
        scid: channel_id.scid,
        vcid: channel_id.vcid,
        cop1_mode: resolve_cop1_mode(state.mission_id, channel_id, interface_id, uplink_pdu),
        tc_stream_id: build_tc_stream_id(state.mission_id, channel_id, interface_id),
        tc_stream_id_raw: nil
      }

      {:reply, {:ok, decision}, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:defer, reason} ->
        {:reply, {:defer, reason}, state}
    end
  end

  defp resolve_channel(mission_id, target_id, opts) do
    channels = TargetDirectory.list_channels(mission_id, target_id)
    channel_override = Keyword.get(opts, :channel_id)
    interface_override = Keyword.get(opts, :interface_id)

    cond do
      match?(%ChannelId{}, channel_override) ->
        if Enum.any?(channels, &(ChannelId.key(&1) == ChannelId.key(channel_override))) do
          {:ok, channel_override}
        else
          {:error, :no_interface}
        end

      channels == [] ->
        {:error, :no_interface}

      is_binary(interface_override) ->
        pick_channel_for_interface(mission_id, channels, interface_override)

      length(channels) == 1 ->
        {:ok, hd(channels)}

      true ->
        pick_channel_by_active(mission_id, channels)
    end
  end

  defp pick_channel_for_interface(mission_id, channels, interface_id) do
    matches =
      Enum.filter(channels, fn channel_id ->
        binding_active?(mission_id, channel_id, interface_id, :uplink)
      end)

    case matches do
      [channel_id] -> {:ok, channel_id}
      [] -> {:error, :no_interface}
      _ -> {:error, :routing_ambiguous}
    end
  end

  defp pick_channel_by_active(mission_id, channels) do
    active =
      Enum.filter(channels, fn channel_id ->
        is_binary(active_interface_for_channel(mission_id, channel_id))
      end)

    case active do
      [channel_id] -> {:ok, channel_id}
      [] -> {:error, :no_interface}
      _ -> {:error, :routing_ambiguous}
    end
  end

  defp select_interface(mission_id, %ChannelId{} = channel_id, opts) do
    requested = Keyword.get(opts, :interface_id)

    cond do
      is_binary(requested) and binding_active?(mission_id, channel_id, requested, :uplink) ->
        {:ok, requested}

      is_binary(requested) ->
        {:error, :no_interface}

      true ->
        case active_interface_for_channel(mission_id, channel_id) do
          nil -> {:error, :no_interface}
          interface_id -> {:ok, interface_id}
        end
    end
  end

  defp active_interface_for_channel(mission_id, %ChannelId{} = channel_id) do
    if link_controller_running?(mission_id, channel_id.scid) do
      LinkController.active_uplink_interface(mission_id, channel_id)
    else
      nil
    end
  end

  defp binding_active?(mission_id, %ChannelId{} = channel_id, interface_id, direction) do
    link_controller_running?(mission_id, channel_id.scid) and
      LinkController.binding_active?(mission_id, channel_id, interface_id, direction)
  end

  defp link_controller_running?(mission_id, scid) do
    Registry.lookup(Cadence.MissionRegistry, {:link_controller, mission_id, scid}) != []
  end

  defp resolve_cop1_mode(mission_id, %ChannelId{} = channel_id, interface_id, uplink_pdu) do
    case protocol_config_for_interface(mission_id, channel_id.scid, interface_id) do
      {:ok, protocol_config} ->
        cop1 = Map.get(protocol_config, :cop1, %{})
        COP1Config.mode_for_config(cop1, uplink_pdu.pdu_type, uplink_pdu.apid)

      :error ->
        :bypass
    end
  end

  defp build_tc_stream_id(mission_id, %ChannelId{} = channel_id, interface_id) do
    TCStreamId.new_from_channel!(mission_id, channel_id, interface_id: interface_id)
  end

  defp protocol_config_for_interface(mission_id, scid, interface_id) do
    if link_controller_running?(mission_id, scid) do
      LinkController.protocol_config_for_interface(mission_id, scid, interface_id)
    else
      :error
    end
  end

  # keep encode helpers in ChannelService; dispatcher only routes
end
