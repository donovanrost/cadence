defmodule Cadence.Runtime.Uplink.RoutingService do
  @moduledoc """
  Resolves uplink routing decisions for target PDUs.
  """

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.CCSDS.Core.PDU
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.ProtocolConfig
  alias Cadence.Runtime.Transport.COP1.Config
  alias Cadence.Runtime.Uplink.{RouteDecision, UplinkPDU}
  alias Cadence.Transport.TCStreamId

  defstruct mission_id: nil,
            routes_by_target: %{},
            protocol_defaults_by_scid: %{},
            channel_protocol_overrides: %{},
            effective_protocols_by_channel: %{}

  @type t :: %__MODULE__{
          mission_id: String.t(),
          routes_by_target: %{optional(String.t()) => [map()]},
          protocol_defaults_by_scid: %{optional(non_neg_integer()) => map()},
          channel_protocol_overrides: %{
            optional({non_neg_integer(), non_neg_integer(), non_neg_integer() | nil}) => map()
          },
          effective_protocols_by_channel: %{
            optional({non_neg_integer(), non_neg_integer(), non_neg_integer() | nil}) => map()
          }
        }

  @spec new(MissionConfig.t()) :: t()
  def new(%MissionConfig{} = config) do
    routes_by_target = build_routes(config.channel_targets, config.bindings)
    protocol_defaults_by_scid = build_protocol_defaults_by_scid(config.links)
    channel_protocol_overrides = build_channel_protocol_overrides(config.links)

    effective_protocols_by_channel =
      build_effective_protocols(
        protocol_defaults_by_scid,
        channel_protocol_overrides,
        config.links
      )

    %__MODULE__{
      mission_id: config.mission_id,
      routes_by_target: routes_by_target,
      protocol_defaults_by_scid: protocol_defaults_by_scid,
      channel_protocol_overrides: channel_protocol_overrides,
      effective_protocols_by_channel: effective_protocols_by_channel
    }
  end

  @spec routes_for_target(t(), String.t()) :: [map()]
  def routes_for_target(%__MODULE__{} = service, target_id) do
    Map.get(service.routes_by_target, target_id, [])
  end

  @spec route(t(), UplinkPDU.t(), keyword()) ::
          {:ok, RouteDecision.t()}
          | {:error, :no_transport}
          | {:error, :routing_ambiguous, list()}
  def route(%__MODULE__{} = service, %UplinkPDU{} = uplink_pdu, opts \\ []) do
    route(service, uplink_pdu.target_id, uplink_pdu.pdu_type, uplink_pdu.apid, opts)
  end

  @spec route(t(), String.t(), PDU.pdu_type() | nil, non_neg_integer() | nil, keyword()) ::
          {:ok, RouteDecision.t()}
          | {:error, :no_transport}
          | {:error, :routing_ambiguous, list()}
  def route(%__MODULE__{} = service, target_id, pdu_type, apid, opts) do
    routes = routes_for_target(service, target_id)

    case select_route(routes, opts) do
      {:ok, route} ->
        {:ok, decision_from_route(service, route, target_id, pdu_type, apid)}

      {:error, :no_transport} ->
        {:error, :no_transport}

      {:error, :routing_ambiguous, candidates} ->
        {:error, :routing_ambiguous, candidates}
    end
  end

  defp select_route(routes, opts) do
    case Keyword.get(opts, :transport_id) do
      nil ->
        case routes do
          [] -> {:error, :no_transport}
          [route] -> {:ok, route}
          _ -> {:error, :routing_ambiguous, routes}
        end

      transport_id ->
        case Enum.find(routes, &(&1.transport_id == transport_id)) do
          nil -> {:error, :no_transport}
          route -> {:ok, route}
        end
    end
  end

  defp decision_from_route(
         %__MODULE__{} = service,
         route,
         target_id,
         pdu_type,
         apid
       ) do
    scid = route.channel_id.scid
    vcid = route.channel_id.vcid

    cop1_mode = resolve_cop1_mode(service, scid, vcid, pdu_type, apid)
    tc_stream_id = build_tc_stream_id(service, route.transport_id, scid, vcid)

    %RouteDecision{
      target_id: target_id,
      pdu_type: pdu_type,
      apid: apid,
      transport_id: route.transport_id,
      scid: scid,
      vcid: vcid,
      cop1_mode: cop1_mode,
      tc_stream_id: tc_stream_id,
      tc_stream_id_raw: nil
    }
  end

  defp build_tc_stream_id(%__MODULE__{} = service, transport_id, scid, vcid) do
    if is_binary(service.mission_id) and is_integer(scid) and is_integer(vcid) do
      TCStreamId.new!(service.mission_id, transport_id, scid, vcid)
    else
      nil
    end
  end

  defp resolve_cop1_mode(%__MODULE__{} = service, scid, vcid, pdu_type, apid) do
    protocol_config =
      case {scid, vcid} do
        {scid, vcid} when is_integer(scid) and is_integer(vcid) ->
          Map.get(service.effective_protocols_by_channel, {scid, vcid, nil}) ||
            Map.get(service.effective_protocols_by_channel, {scid, vcid, 0})

        _ ->
          nil
      end

    protocol_config =
      if is_map(protocol_config) do
        protocol_config
      else
        defaults = Map.get(service.protocol_defaults_by_scid, scid, %{})

        if defaults == %{} do
          nil
        else
          ProtocolConfig.effective_config(defaults, %{}, scid: scid)
        end
      end

    case protocol_config do
      %{} = config ->
        cop1 = Map.get(config, :cop1, %{})
        Config.mode_for_config(cop1, pdu_type, apid)

      _ ->
        :bypass
    end
  end

  defp build_routes(nil, _bindings), do: %{}
  defp build_routes([], _bindings), do: %{}

  defp build_routes(channel_targets, bindings) when is_list(channel_targets) do
    bindings_by_channel =
      bindings
      |> List.wrap()
      |> Enum.filter(fn binding -> binding_uplink?(binding) and binding_channel?(binding) end)
      |> Enum.group_by(&channel_key(&1.channel))

    channel_targets
    |> Enum.reduce(%{}, fn channel_target, acc ->
      with %ChannelId{} = channel_id <- channel_id_from_target(channel_target),
           bindings when is_list(bindings) <-
             Map.get(bindings_by_channel, ChannelId.key(channel_id), []) do
        routes =
          Enum.map(bindings, fn binding ->
            %{
              target_id: channel_target.target_id,
              channel_id: channel_id,
              transport_id: binding.transport_id,
              binding: binding
            }
          end)

        Map.update(acc, channel_target.target_id, routes, &(&1 ++ routes))
      else
        _ -> acc
      end
    end)
  end

  defp binding_uplink?(binding) do
    binding.direction in [:uplink, :both] and binding.desired_state in [:active, :draining]
  end

  defp binding_channel?(binding) do
    case binding.channel do
      %{scid: scid, vcid: vcid} when is_integer(scid) and is_integer(vcid) -> true
      _ -> false
    end
  end

  defp channel_key(channel) do
    ChannelId.key(ChannelId.new(channel.scid, channel.vcid, channel.map_id))
  end

  defp channel_id_from_target(channel_target) do
    if is_integer(channel_target.scid) and is_integer(channel_target.vcid) do
      ChannelId.new(channel_target.scid, channel_target.vcid, channel_target.map_id)
    else
      nil
    end
  end

  defp build_protocol_defaults_by_scid(links) do
    Enum.reduce(links || [], %{}, fn link, acc ->
      defaults =
        case Map.get(link, :protocol_config) do
          nil -> %{}
          config -> Map.get(config, :config, %{})
        end

      Map.put(acc, link.scid, defaults || %{})
    end)
  end

  defp build_channel_protocol_overrides(links) do
    links
    |> List.wrap()
    |> Enum.flat_map(&channel_override_entries/1)
    |> Map.new()
  end

  defp build_effective_protocols(defaults_by_scid, overrides_by_channel, links) do
    links
    |> List.wrap()
    |> Enum.flat_map(&effective_protocol_entries(&1, defaults_by_scid, overrides_by_channel))
    |> Map.new()
  end

  defp channel_override_entries(link) do
    link
    |> Map.get(:channels, [])
    |> Enum.flat_map(&channel_override_entry/1)
  end

  defp channel_override_entry(channel) do
    channel_id = ChannelId.new(channel.scid, channel.vcid, channel.map_id)

    overrides =
      case Map.get(channel, :protocol_config) do
        nil -> nil
        config -> Map.get(config, :overrides, %{})
      end

    if is_map(overrides) and overrides != %{} do
      [{ChannelId.key(channel_id), overrides}]
    else
      []
    end
  end

  defp effective_protocol_entries(link, defaults_by_scid, overrides_by_channel) do
    defaults = Map.get(defaults_by_scid, link.scid, %{})

    link
    |> Map.get(:channels, [])
    |> Enum.flat_map(fn channel ->
      channel_id = ChannelId.new(channel.scid, channel.vcid, channel.map_id)
      overrides = Map.get(overrides_by_channel, ChannelId.key(channel_id), %{})

      if defaults == %{} and overrides == %{} do
        []
      else
        effective = ProtocolConfig.effective_config(defaults, overrides, scid: link.scid)
        [{ChannelId.key(channel_id), effective}]
      end
    end)
  end
end
