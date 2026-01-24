defmodule Cadence.CCSDS.PDUDispatcher do
  @moduledoc """
  Dispatches decoded PDUs to application handlers and publishes their events.
  """

  use GenServer
  require Logger

  alias Cadence.Events.TelemetryPacket
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Transport.COP1.ReportHandler

  @default_handlers [ReportHandler, Cadence.Telemetry.PDUHandler]

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    channel_id = Keyword.fetch!(opts, :channel_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(mission_id, channel_id))
  end

  def via_tuple(mission_id, channel_id) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:pdu_dispatcher, mission_id, channel_id_key(channel_id)}}}
  end

  def ingest(dispatcher, pdu, ctx) do
    GenServer.cast(dispatcher, {:pdu, pdu, ctx})
  end

  @impl true
  def init(opts) do
    handlers = load_handlers(opts)
    cop1_report_apids = cop1_report_apids(opts)

    handler_states =
      Enum.reduce(handlers, %{}, fn handler, acc ->
        case handler.init(opts) do
          {:ok, state} ->
            Map.put(acc, handler, state)

          {:error, reason} ->
            Logger.warning("PDU handler #{inspect(handler)} failed to init: #{inspect(reason)}")
            acc
        end
      end)

    state = %{
      handlers: handlers,
      handler_states: handler_states,
      cop1_report_apids: cop1_report_apids
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:pdu, pdu, ctx}, state) do
    ctx = Map.put_new(ctx, :cop1_report_apids, state.cop1_report_apids)
    {events, new_state} = dispatch_to_handlers(pdu, ctx, state)
    emit_events(events)
    {:noreply, new_state}
  end

  defp load_handlers(opts) do
    Keyword.get(opts, :handlers, Application.get_env(:cadence, :pdu_handlers, @default_handlers))
  end

  defp cop1_report_apids(opts) do
    opts
    |> Keyword.get(:protocol_config, %{})
    |> report_apids_from_protocol()
    |> MapSet.new()
  end

  defp report_apids_from_protocol(%{cop1_report_apids: apids}) do
    normalize_apids(apids)
  end

  defp report_apids_from_protocol(%{cop1: cop1}) when is_map(cop1) do
    apids =
      fetch_value(cop1, "report_apids") ||
        fetch_value(cop1, "report_apid")

    normalize_apids(apids)
  end

  defp report_apids_from_protocol(_protocol_config), do: []

  defp normalize_apids(nil), do: []

  defp normalize_apids(apids) when is_list(apids) do
    apids
    |> Enum.map(&parse_integer/1)
    |> Enum.filter(&is_integer/1)
  end

  defp normalize_apids(value) do
    case parse_integer(value) do
      nil -> []
      apid -> [apid]
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp fetch_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, String.to_atom(key))
  rescue
    _ -> Map.get(config, key)
  end

  defp channel_id_key(%ChannelId{} = channel_id) do
    ChannelId.key(channel_id)
  end

  defp channel_id_key(channel_id), do: channel_id

  defp dispatch_to_handlers(pdu, ctx, state) do
    Enum.reduce(state.handlers, {[], state}, fn handler, {events, acc_state} ->
      if handler.accepts?(pdu, ctx) do
        {handler_events, updated_state} = invoke_handler(handler, pdu, ctx, acc_state)
        {events ++ handler_events, updated_state}
      else
        {events, acc_state}
      end
    end)
  end

  defp invoke_handler(handler, pdu, ctx, state) do
    handler_state = Map.get(state.handler_states, handler)

    case handler.handle_pdu(pdu, ctx, handler_state) do
      {:ok, events, new_handler_state} ->
        {events, put_in(state.handler_states[handler], new_handler_state)}

      {:skip, reason, new_handler_state} ->
        Logger.debug("PDU handler #{inspect(handler)} skipped: #{inspect(reason)}")
        {[], put_in(state.handler_states[handler], new_handler_state)}

      {:error, reason, new_handler_state} ->
        Logger.warning("PDU handler #{inspect(handler)} failed: #{inspect(reason)}")
        {[], put_in(state.handler_states[handler], new_handler_state)}
    end
  end

  defp emit_events(events) do
    Enum.each(events, &emit_event/1)
  end

  defp emit_event(%TelemetryPacket{} = event) do
    case telemetry_topic(event) do
      {:ok, topic} ->
        Phoenix.PubSub.broadcast(
          Cadence.PubSub,
          topic,
          {:telemetry_packet, event.packet, event.metadata}
        )

      {:error, reason} ->
        Logger.warning("Unable to emit telemetry packet event: #{inspect(reason)}")
    end
  end

  defp emit_event(_event), do: :ok

  defp telemetry_topic(%TelemetryPacket{} = event) do
    mission_id = event.packet.mission_id || event.metadata[:mission_id]

    if mission_id do
      {:ok, "mission:#{mission_id}:telemetry:raw"}
    else
      {:error, :missing_mission_id}
    end
  end
end
