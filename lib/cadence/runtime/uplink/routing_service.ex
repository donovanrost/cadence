defmodule Cadence.Runtime.Uplink.RoutingService do
  @moduledoc """
  Resolves uplink routing decisions for target PDUs.
  """

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.CCSDS.Core.PDU
  alias Cadence.Domain.Interfaces.Entities.TargetInterface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Transport.COP1.Config
  alias Cadence.Runtime.Uplink.{RouteDecision, UplinkPDU}
  alias Cadence.Transport.TCStreamId

  defstruct mission_id: nil,
            routes_by_target: %{},
            interfaces_by_id: %{},
            interface_defaults: %{},
            vcid_by_target: %{},
            vcid_defaults: %{}

  @type t :: %__MODULE__{
          mission_id: String.t(),
          routes_by_target: %{optional(String.t()) => [TargetInterface.t()]},
          interfaces_by_id: %{optional(String.t()) => term()},
          interface_defaults: %{optional(String.t()) => map()},
          vcid_by_target: %{optional({String.t(), String.t()}) => non_neg_integer()},
          vcid_defaults: %{optional(String.t()) => non_neg_integer()}
        }

  @spec new(MissionConfig.t()) :: t()
  def new(%MissionConfig{} = config) do
    routes_by_target =
      config.target_interface_routings
      |> Enum.filter(&TargetInterface.allows_write?/1)
      |> Enum.group_by(& &1.target_id)

    interfaces_by_id = Map.new(config.interfaces, fn interface -> {interface.id, interface} end)

    interface_defaults = build_interface_defaults(config.interfaces)
    {vcid_by_target, vcid_defaults} = index_vcids(config.interface_vcids)

    %__MODULE__{
      mission_id: config.mission_id,
      routes_by_target: routes_by_target,
      interfaces_by_id: interfaces_by_id,
      interface_defaults: interface_defaults,
      vcid_by_target: vcid_by_target,
      vcid_defaults: vcid_defaults
    }
  end

  @spec routes_for_target(t(), String.t()) :: [TargetInterface.t()]
  def routes_for_target(%__MODULE__{} = service, target_id) do
    Map.get(service.routes_by_target, target_id, [])
  end

  @spec route(t(), UplinkPDU.t(), keyword()) ::
          {:ok, RouteDecision.t()}
          | {:error, :no_interface}
          | {:error, :routing_ambiguous, list()}
  def route(%__MODULE__{} = service, %UplinkPDU{} = uplink_pdu, opts \\ []) do
    route(service, uplink_pdu.target_id, uplink_pdu.pdu_type, uplink_pdu.apid, opts)
  end

  @spec route(t(), String.t(), PDU.pdu_type() | nil, non_neg_integer() | nil, keyword()) ::
          {:ok, RouteDecision.t()}
          | {:error, :no_interface}
          | {:error, :routing_ambiguous, list()}
  def route(%__MODULE__{} = service, target_id, pdu_type, apid, opts) do
    routes = routes_for_target(service, target_id)

    case select_route(routes, opts) do
      {:ok, route} ->
        {:ok, decision_from_route(service, route, target_id, pdu_type, apid)}

      {:error, :no_interface} ->
        {:error, :no_interface}

      {:error, :routing_ambiguous, candidates} ->
        {:error, :routing_ambiguous, candidates}
    end
  end

  defp select_route(routes, opts) do
    case Keyword.get(opts, :interface_id) do
      nil ->
        case routes do
          [] -> {:error, :no_interface}
          [route] -> {:ok, route}
          _ -> {:error, :routing_ambiguous, routes}
        end

      interface_id ->
        case Enum.find(routes, &(&1.interface_id == interface_id)) do
          nil -> {:error, :no_interface}
          route -> {:ok, route}
        end
    end
  end

  defp decision_from_route(
         %__MODULE__{} = service,
         %TargetInterface{} = route,
         target_id,
         pdu_type,
         apid
       ) do
    defaults = Map.get(service.interface_defaults, route.interface_id, %{})

    scid =
      case route.scid do
        scid when is_integer(scid) -> scid
        _ -> Map.get(defaults, :scid)
      end

    vcid =
      Map.get(service.vcid_by_target, {route.interface_id, target_id}) ||
        Map.get(service.vcid_defaults, route.interface_id) ||
        Map.get(defaults, :vcid)

    cop1_mode = resolve_cop1_mode(service, route.interface_id, pdu_type, apid)
    tc_stream_id = build_tc_stream_id(service, route.interface_id, scid, vcid, defaults)

    %RouteDecision{
      target_id: target_id,
      pdu_type: pdu_type,
      apid: apid,
      interface_id: route.interface_id,
      scid: scid,
      vcid: vcid,
      cop1_mode: cop1_mode,
      tc_stream_id: tc_stream_id,
      tc_stream_id_raw: route.tc_stream_id
    }
  end

  defp build_tc_stream_id(%__MODULE__{} = service, interface_id, scid, vcid, defaults) do
    if is_binary(service.mission_id) and is_integer(scid) and is_integer(vcid) do
      TCStreamId.new!(service.mission_id, interface_id, scid, vcid, map_id: defaults[:map_id])
    else
      nil
    end
  end

  defp resolve_cop1_mode(%__MODULE__{} = service, interface_id, pdu_type, apid) do
    case Map.get(service.interfaces_by_id, interface_id) do
      nil -> :bypass
      interface -> Config.mode_for(interface, pdu_type, apid)
    end
  end

  defp build_interface_defaults(interfaces) do
    Enum.reduce(interfaces, %{}, fn interface, acc ->
      defaults =
        case SDLPConfig.fetch(interface) do
          {:ok, %{opts: opts}} ->
            %{
              scid: opts[:uplink_scid],
              vcid: opts[:uplink_vcid],
              map_id: opts[:uplink_map_id]
            }

          :error ->
            %{}
        end

      Map.put(acc, interface.id, defaults)
    end)
  end

  defp index_vcids(nil), do: {%{}, %{}}
  defp index_vcids([]), do: {%{}, %{}}

  defp index_vcids(vcid_mappings) when is_list(vcid_mappings) do
    Enum.reduce(vcid_mappings, {%{}, %{}}, fn mapping, {by_target, defaults} ->
      interface_id = mapping.interface_id
      vcid = mapping.vcid
      target_id = mapping.target_id

      if is_binary(target_id) do
        {Map.put(by_target, {interface_id, target_id}, vcid), defaults}
      else
        {by_target, Map.put(defaults, interface_id, vcid)}
      end
    end)
  end
end
