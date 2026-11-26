defmodule Cadence.Runtime.PartitionOwner.CurrentValueSeed do
  @moduledoc """
  Seeds the ETS current-value store from a recovered partition's snapshot (DECISIONS #96, #831).

  After a node restart the store is empty until each spacecraft's next frame, and at 500+ craft
  most are not in contact. The snapshot holds each parameter's `latest` update, so a starting
  owner puts those into the store (`Storage.seed_current_values/3`): every value with its OWN
  generation and receipt time, so the staleness rules still say stale, and never over a value the
  store already has that is newer.

  What can be seeded is what the snapshot holds: the parameters the mission model's semantic plan
  evaluates (monitoring and algorithms), not every telemetry point. A container parameter is
  carries the point it came from (`metadata.point_id`, set when the update is made); an algorithm
  output is built the way its live derived sample is (`derived_sample`). A parameter with no point
  (a snapshot written before the point was carried) is skipped and counted.
  Only the ETS store is seeded: the Postgres store is not a cache and its rows have referential
  ties a snapshot cannot supply.
  """

  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticRuntime.{State, Update}
  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage

  @doc """
  Seeds the store from `semantic_state.latest`. `derived_sample` builds the sample of an algorithm
  output (the partition owner's own). `{:ok, %{seeded: n, skipped: m}}`.
  """
  @spec seed(map(), State.t(), (Update.t() -> Sample.t())) ::
          {:ok, %{seeded: non_neg_integer(), skipped: non_neg_integer()}} | {:error, term()}
  def seed(state, %State{latest: latest}, derived_sample) when map_size(latest) > 0 do
    policy = state.persistence_policy.telemetry_storage

    if ets?(policy) do
      started = System.monotonic_time()

      samples =
        latest |> Map.values() |> Enum.map(&sample(&1, derived_sample)) |> Enum.reject(&is_nil/1)

      skipped = map_size(latest) - length(samples)

      with :ok <-
             Storage.seed_current_values(policy, samples,
               organization_id: state.active_activation.organization_id,
               source_endpoint_id: source_endpoint(state.partition_key),
               metadata: %{seeded_from: "semantic_snapshot"}
             ) do
        :telemetry.execute(
          [:cadence, :runtime, :partition, :current_values_seeded],
          %{
            seeded: length(samples),
            skipped: skipped,
            duration_ms:
              System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
          },
          %{
            mission_id: state.mission_id,
            partition_id: PartitionKey.identifier(state.partition_key)
          }
        )

        {:ok, %{seeded: length(samples), skipped: skipped}}
      end
    else
      {:ok, %{seeded: 0, skipped: 0}}
    end
  end

  def seed(_state, _semantic_state, _derived_sample), do: {:ok, %{seeded: 0, skipped: 0}}

  defp ets?(%{current_value_store_policy: %{backend: CurrentValueStore.ETS}}), do: true
  defp ets?(_policy), do: false

  defp sample(%Update{producer_kind: :algorithm} = update, derived_sample),
    do: derived_sample.(update)

  defp sample(%Update{} = update, _derived_sample) do
    case meta(update, :point_id) do
      nil ->
        nil

      point_id ->
        %Sample{
          sample_id: update.update_id,
          mission_id: meta(update, :mission_id),
          spacecraft_id: meta(update, :spacecraft_id),
          point_id: point_id,
          point_name: point_id,
          semantic_id: update.parameter_id,
          qualified_name: update.qualified_name,
          producer_kind: update.producer_kind,
          producer_id: update.producer_id,
          packet_definition_id: update.producer_id,
          packet_definition_version: 1,
          packet_id: meta(update, :packet_id) || update.update_id,
          evidence_id: meta(update, :evidence_id) || update.update_id,
          raw_value: update.raw_value,
          engineering_value: update.value,
          quality_state: update.quality,
          generation_time: update.generation_time,
          receipt_time: update.receipt_time,
          provenance: %{seeded_from: "semantic_snapshot"}
        }
    end
  end

  defp meta(update, key),
    do: Map.get(update.metadata, key, Map.get(update.metadata, Atom.to_string(key)))

  defp source_endpoint(%PartitionKey{affinity: :source_endpoint, value: value}), do: value
  defp source_endpoint(_key), do: nil
end
