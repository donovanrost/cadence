defmodule Cadence.Runtime.Telemetry.ConfigBundle do
  @moduledoc """
  Versioned config bundle stored in persistent_term for data plane access.
  """

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.Telemetry.DerivedItems.Cache, as: DerivedItemsCache
  alias Cadence.Runtime.Telemetry.PacketCatalog

  @type t :: %__MODULE__{
          mission_id: String.t(),
          config_version: non_neg_integer(),
          packet_defs: list(),
          packet_catalog: map(),
          targets: list(),
          derived_item_defs: list(),
          derived_defs: list(),
          derived_packet_index: map(),
          limit_defs: map()
        }

  defstruct [
    :mission_id,
    :config_version,
    packet_defs: [],
    packet_catalog: %{},
    targets: [],
    derived_item_defs: [],
    derived_defs: [],
    derived_packet_index: %{},
    limit_defs: %{}
  ]

  @spec from_config(MissionConfig.t()) :: t()
  def from_config(%MissionConfig{} = config) do
    {derived_defs, derived_packet_index} =
      case DerivedItemsCache.prepare_defs(config.derived_item_defs) do
        {:ok, {defs, packet_index}} -> {defs, packet_index}
        _ -> {[], %{}}
      end

    packet_catalog_defs = Map.get(config, :packet_catalog_defs, [])

    %__MODULE__{
      mission_id: config.mission_id,
      config_version: config.config_generation,
      packet_defs: config.packet_defs,
      packet_catalog: build_packet_catalog(packet_catalog_defs, config.targets),
      targets: config.targets,
      derived_item_defs: config.derived_item_defs,
      derived_defs: derived_defs,
      derived_packet_index: derived_packet_index,
      limit_defs: config.limit_defs
    }
  end

  @spec store(t()) :: :ok
  def store(%__MODULE__{} = bundle) do
    :persistent_term.put(key(bundle.mission_id), bundle)
    :ok
  end

  @spec fetch(String.t()) :: {:ok, t()} | {:error, :not_found}
  def fetch(mission_id) when is_binary(mission_id) do
    case :persistent_term.get(key(mission_id), nil) do
      nil -> {:error, :not_found}
      bundle -> {:ok, bundle}
    end
  end

  defp key(mission_id), do: {:cadence, :config_bundle, mission_id}

  defp build_packet_catalog(packet_catalog_defs, targets)
       when is_list(packet_catalog_defs) and is_list(targets) do
    if packet_catalog_defs != [] do
      PacketCatalog.build_catalog(packet_catalog_defs, targets)
    else
      %{}
    end
  end

  defp build_packet_catalog(_packet_catalog_defs, _targets), do: %{}
end
