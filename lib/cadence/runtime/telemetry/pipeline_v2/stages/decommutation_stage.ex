defmodule Cadence.Runtime.Telemetry.PipelineV2.Stages.DecommutationStage do
  @moduledoc """
  Pipeline stage that extracts telemetry items from packet payload.

  Uses the packet definition from IdentifyStage to parse binary data
  into named telemetry items with raw values.

  ## Input

  PipelineEvent with:
  - `packet` - Raw Packet struct
  - `packet_def` - Packet definition (from IdentifyStage)
  - `packet_format` - Format atom (:ccsds, :simulator)

  ## Output

  PipelineEvent enriched with:
  - `raw_items` - Map of item_name => raw_value (before conversions)
  """

  use Cadence.Runtime.Telemetry.PipelineV2.Stages.StageBehaviour

  alias Cadence.Telemetry.{Decommutation, Packet}

  @impl true
  def stage_name, do: :decom

  @impl true
  def process(event, _state) do
    %{packet: packet, packet_def: packet_def, packet_format: packet_format} = event

    case Packet.get_payload(packet) do
      {:ok, payload} ->
        case Decommutation.decommutate(payload, packet_def, packet_format) do
          {:ok, raw_items} ->
            {:ok, %{event | raw_items: raw_items}}

          {:error, reason} ->
            {:error, {:decommutation_failed, packet_def.name, reason}}
        end

      {:error, reason} ->
        {:error, {:payload_extraction_failed, reason}}
    end
  end
end
