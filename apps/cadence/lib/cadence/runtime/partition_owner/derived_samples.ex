defmodule Cadence.Runtime.PartitionOwner.DerivedSamples do
  @moduledoc """
  The samples a partition owner emits for an algorithm's derived parameters. A derived value
  shares its trigger's time, identity ref and (#1078 E1a) origin.
  """

  alias Cadence.SemanticRuntime.Update
  alias Cadence.Telemetry.Sample

  @doc """
  The origin of each sample of a batch, by sample id: a derived value takes its trigger's (#1078
  E1a). Built once per batch, not per derived sample.
  """
  @spec origins([term()]) :: %{binary() => map()}
  def origins(outputs) do
    for %Sample{origin: %{} = origin, sample_id: id} <- outputs, into: %{}, do: {id, origin}
  end

  @doc """
  The sample of an algorithm's parameter update. `origins` is `origins/1` of the batch the trigger
  was in; a timer-triggered value has no trigger sample, so no origin.
  """
  @spec build(Update.t(), map(), %{binary() => map()}) :: Sample.t()
  def build(%Update{} = update, activation, origins \\ %{}) do
    algorithm_plan = Map.get(activation.runtime_plans, :algorithm)

    %Sample{
      sample_id: update.update_id,
      mission_id: metadata_value(update, :mission_id),
      spacecraft_id: metadata_value(update, :spacecraft_id),
      point_id: update.parameter_id,
      point_name: update.qualified_name,
      semantic_id: update.parameter_id,
      qualified_name: update.qualified_name,
      producer_kind: :algorithm,
      producer_id: update.producer_id,
      mission_model_revision_id: activation.mission_model_revision_id,
      runtime_plan_id: algorithm_plan && algorithm_plan.plan_id,
      packet_definition_id: "mission_model_algorithm:" <> update.producer_id,
      packet_definition_version: 1,
      packet_id: metadata_value(update, :packet_id) || update.update_id,
      evidence_id: metadata_value(update, :evidence_id) || update.update_id,
      raw_value: nil,
      engineering_value: update.value,
      quality_state: update.quality,
      generation_time: update.generation_time,
      receipt_time: update.receipt_time,
      # A derived value shares its trigger's time, so it shares its trigger's identity ref too.
      generation_time_source: time_source(metadata_value(update, :generation_time_source)),
      frame_ref: Sample.decode_frame_ref(metadata_value(update, :trigger_frame_ref)),
      origin: Map.get(origins, metadata_value(update, :trigger_sample_id)),
      provenance: %{
        source_update_ids: update.source_update_ids,
        trigger_sample_id: metadata_value(update, :trigger_sample_id),
        mission_model_revision_id: activation.mission_model_revision_id,
        runtime_plan_id: algorithm_plan && algorithm_plan.plan_id,
        producer_kind: :algorithm,
        producer_id: update.producer_id
      }
    }
  end

  defp metadata_value(update, key),
    do: Map.get(update.metadata, key, Map.get(update.metadata, Atom.to_string(key)))

  defp time_source(source) when source in [:receipt, "receipt"], do: :receipt
  defp time_source(source) when source in [:onboard, "onboard"], do: :onboard
  defp time_source(_source), do: nil
end
