defmodule Cadence.IngressJournal.IngestTelemetry do
  @moduledoc """
  The ingest path's throughput and lag as `:telemetry` events (#686), so a load run (platform's
  500/1,000-spacecraft harness, `mix cadence.profile`) can read frames/s, samples/s and journal
  lag per contact path without instrumenting the pipeline again.

  * `[:cadence, :ingest, :batch, :stop]`: one per journal batch, when its semantic persistence is
    acknowledged (the processing cursor advances).
    Measurements: `entries`, `bytes`, `frames`, `packets`, `samples` (decoded and derived),
    `duration_us` (delivery to the executor until acknowledgement) and `journal_lag_ms` (now minus
    the receipt time of the batch's first entry). A batch acknowledged after a restart resumed it
    has no delivery time or counts: `duration_us` and the three counts are then left out, never
    reported as 0, so they don't drag an average down.
  * `[:cadence, :ingest, :journal, :backlog]`: per journal (one per contact path), at most once a
    second, from the journal's own checkpoint timer.
    Measurements: `bytes` (appended but not yet acknowledged by processing: measured from the
    in-memory processing cursor, unlike the snapshot's `processing_backlog`, which starts from the
    durable one) and `oldest_unacked_age_ms` (0 when nothing is waiting).

  Both carry `mission_id`, `path_id`, `provider_binding_id` and `realized_contact_id` as metadata.
  At 1,000 paths the batch event fires a few thousand times a second: handlers should aggregate,
  not store each event. `path_id` and `realized_contact_id` are unbounded (one per contact): never
  map them to a metric label (the metrics catalog forbids them as attributes).
  """

  alias Cadence.Telemetry.Sample

  @batch_stop [:cadence, :ingest, :batch, :stop]
  @journal_backlog [:cadence, :ingest, :journal, :backlog]

  @type counts :: %{
          frames: non_neg_integer(),
          packets: non_neg_integer(),
          samples: non_neg_integer()
        }

  @spec batch_stop_event() :: [atom()]
  def batch_stop_event, do: @batch_stop

  @spec journal_backlog_event() :: [atom()]
  def journal_backlog_event, do: @journal_backlog

  @doc "What one partition processing result carried, for the batch event."
  @spec counts(map()) :: counts()
  def counts(result) when is_map(result) do
    %{
      frames: result |> Map.get(:transfer_frame_records, []) |> length(),
      packets: result |> Map.get(:packet_records, []) |> length(),
      samples: result |> Map.get(:outputs, []) |> Enum.count(&match?(%Sample{}, &1))
    }
  end

  @doc """
  Emits the batch event for an acknowledged journal batch. `batch` is the consumer's in-flight
  batch (`first`, `entry_count`, `byte_count`, `delivered_at`, `counts`); `context` the path's ids.
  """
  @spec batch_acknowledged(map(), map()) :: :ok
  def batch_acknowledged(batch, context) do
    measurements =
      %{
        entries: batch.entry_count,
        bytes: batch.byte_count,
        journal_lag_ms:
          max(DateTime.diff(DateTime.utc_now(), batch.first.receipt_time, :millisecond), 0)
      }
      |> Map.merge(Map.take(Map.get(batch, :counts) || %{}, [:frames, :packets, :samples]))
      |> put_duration(Map.get(batch, :delivered_at))

    :telemetry.execute(@batch_stop, measurements, metadata(context))
  end

  # Unknown after a restart resumed the batch: left out rather than reported as 0.
  defp put_duration(measurements, nil), do: measurements

  defp put_duration(measurements, delivered_at) do
    Map.put(
      measurements,
      :duration_us,
      System.convert_time_unit(System.monotonic_time() - delivered_at, :native, :microsecond)
    )
  end

  @doc "Emits the backlog event for one journal: unacknowledged bytes and the oldest one's age."
  @spec journal_backlog(map(), non_neg_integer(), DateTime.t() | nil) :: :ok
  def journal_backlog(context, bytes, oldest_receipt_time) do
    age_ms =
      case oldest_receipt_time do
        nil -> 0
        %DateTime{} = at -> max(DateTime.diff(DateTime.utc_now(), at, :millisecond), 0)
      end

    :telemetry.execute(
      @journal_backlog,
      %{bytes: bytes, oldest_unacked_age_ms: age_ms},
      metadata(context)
    )
  end

  defp metadata(context) do
    Map.take(context, [:mission_id, :path_id, :provider_binding_id, :realized_contact_id])
  end
end
