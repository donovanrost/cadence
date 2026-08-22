defmodule Cadence.Telemetry.Storage.QuestDB.Smoke do
  @moduledoc """
  End-to-end smoke check for Cadence-managed QuestDB telemetry storage.
  """

  alias Cadence.Telemetry.Sample

  alias Cadence.Telemetry.Storage.{
    ObservationEnvelope,
    QuestDB.ObservationReader,
    QuestDB.ObservationWriter,
    QuestDB.SchemaMigrator,
    WriteContext
  }

  @default_organization_id "questdb-smoke-org"
  @default_mission_id "questdb-smoke-mission"
  @default_point_id "SMOKE.counter"
  @default_data_source_id "managed_questdb_primary"
  @default_binding_id "managed_telemetry_history"

  @type result :: %{
          sample_id: binary(),
          mission_id: binary(),
          point_id: binary(),
          value: integer(),
          bounded_history_count: non_neg_integer(),
          decimated_bucket_count: non_neg_integer(),
          watermark: map(),
          applied_migrations: [SchemaMigrator.migration()]
        }

  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts \\ []) when is_list(opts) do
    value = Keyword.get(opts, :value, System.unique_integer([:positive]))

    with {:ok, applied_migrations} <- SchemaMigrator.apply_pending(opts),
         {:ok, context} <- write_context(opts),
         sample <- sample(value, opts),
         {:ok, envelope} <- ObservationEnvelope.from_sample(context, sample),
         :ok <- ObservationWriter.persist_envelopes([envelope], opts),
         {:ok, samples} <- read_back(sample, opts, 10),
         :ok <- assert_round_trip(samples, sample),
         {:ok, buckets} <- read_decimated_back(sample, opts),
         :ok <- assert_decimation(buckets, sample),
         {:ok, watermark} <- read_watermark(sample, opts),
         :ok <- assert_watermark(watermark, sample) do
      {:ok,
       %{
         sample_id: sample.sample_id,
         mission_id: sample.mission_id,
         point_id: sample.point_id,
         value: value,
         bounded_history_count: length(samples),
         decimated_bucket_count: length(buckets),
         watermark: watermark,
         applied_migrations: applied_migrations
       }}
    end
  end

  defp write_context(opts) do
    WriteContext.new(
      organization_id: Keyword.get(opts, :organization_id, @default_organization_id),
      mission_id: Keyword.get(opts, :mission_id, @default_mission_id),
      realm: Keyword.get(opts, :realm, :flight),
      data_source_id: Keyword.get(opts, :data_source_id, @default_data_source_id),
      binding_id: Keyword.get(opts, :binding_id, @default_binding_id),
      source_endpoint_id: Keyword.get(opts, :source_endpoint_id, "questdb-smoke"),
      recorded_at: timestamp(opts),
      metadata: %{source: :questdb_smoke}
    )
  end

  defp sample(value, opts) do
    timestamp = timestamp(opts)
    sample_id = Keyword.get(opts, :sample_id, "sample-smoke-#{value}")

    %Sample{
      sample_id: sample_id,
      mission_id: Keyword.get(opts, :mission_id, @default_mission_id),
      spacecraft_id: Keyword.get(opts, :spacecraft_id, "smoke-spacecraft"),
      point_id: Keyword.get(opts, :point_id, @default_point_id),
      point_name: Keyword.get(opts, :point_name, @default_point_id),
      packet_definition_id: "smoke-packet-def",
      packet_definition_version: 1,
      packet_id: "packet-#{sample_id}",
      evidence_id: "evidence-#{sample_id}",
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: timestamp,
      receipt_time: timestamp,
      provenance: %{source: :questdb_smoke}
    }
  end

  defp read_back(%Sample{} = sample, opts, attempts_remaining) do
    read_opts =
      opts
      |> Keyword.put(
        :organization_id,
        Keyword.get(opts, :organization_id, @default_organization_id)
      )
      |> Keyword.put(:realm, Keyword.get(opts, :realm, :flight))
      |> Keyword.put(:data_source_id, Keyword.get(opts, :data_source_id, @default_data_source_id))
      |> Keyword.put(:spacecraft_id, sample.spacecraft_id)
      |> Keyword.put(:order, :desc)
      |> Keyword.put(:limit, 10)
      |> Keyword.put(:identity_states, [])

    case ObservationReader.sample_history_result(sample.mission_id, sample.point_id, read_opts) do
      {:ok, %{samples: samples}} ->
        if Enum.any?(samples, &(&1.sample_id == sample.sample_id)) or attempts_remaining <= 1 do
          {:ok, samples}
        else
          Process.sleep(100)
          read_back(sample, opts, attempts_remaining - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_decimated_back(%Sample{} = sample, opts) do
    read_opts = source_read_opts(sample, opts)

    case ObservationReader.decimated_history_result(sample.mission_id, sample.point_id, read_opts) do
      {:ok, %{buckets: buckets}} -> {:ok, buckets}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_watermark(%Sample{} = sample, opts) do
    ObservationReader.sample_watermark_result(
      sample.mission_id,
      sample.point_id,
      source_read_opts(sample, opts)
    )
  end

  defp source_read_opts(%Sample{} = sample, opts) do
    opts
    |> Keyword.put(
      :organization_id,
      Keyword.get(opts, :organization_id, @default_organization_id)
    )
    |> Keyword.put(:realm, Keyword.get(opts, :realm, :flight))
    |> Keyword.put(:data_source_id, Keyword.get(opts, :data_source_id, @default_data_source_id))
    |> Keyword.put(:source_binding_id, Keyword.get(opts, :binding_id, @default_binding_id))
    |> Keyword.put(:spacecraft_id, sample.spacecraft_id)
    |> Keyword.put(:from_receipt_time, sample.receipt_time)
    |> Keyword.put(:to_receipt_time, sample.receipt_time)
    |> Keyword.put(:bucket_width_ms, Keyword.get(opts, :bucket_width_ms, 60_000))
  end

  defp assert_round_trip(samples, %Sample{} = sample) do
    if Enum.any?(
         samples,
         &(&1.sample_id == sample.sample_id and &1.engineering_value == sample.engineering_value)
       ) do
      :ok
    else
      {:error, {:sample_not_read_back, sample.sample_id}}
    end
  end

  defp assert_decimation(buckets, %Sample{} = sample) do
    if Enum.any?(buckets, fn bucket ->
         bucket.sample_count > 0 and bucket.min <= sample.engineering_value and
           bucket.max >= sample.engineering_value
       end) do
      :ok
    else
      {:error, {:sample_not_decimated, sample.sample_id}}
    end
  end

  defp assert_watermark(watermark, %Sample{} = sample) do
    latest_receipt_time =
      if is_map(watermark) do
        Map.get(watermark, :latest_receipt_time)
      end

    case latest_receipt_time do
      %DateTime{} ->
        if watermark.sample_count > 0 and
             DateTime.compare(latest_receipt_time, sample.receipt_time) != :lt do
          :ok
        else
          {:error, {:sample_not_watermarked, sample.sample_id, watermark}}
        end

      _other ->
        {:error, {:sample_not_watermarked, sample.sample_id, watermark}}
    end
  end

  defp timestamp(opts) do
    Keyword.get(opts, :timestamp, DateTime.utc_now())
  end
end
