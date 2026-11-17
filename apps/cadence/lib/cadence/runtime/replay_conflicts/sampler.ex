defmodule Cadence.Runtime.ReplayConflicts.Sampler do
  @moduledoc """
  Every 10 s (#99 follow-up, devops 11-17): each open stuck-processing record on a journal stream
  gets its stream's buffer reading from the journal's own snapshot (`buffer_retained_bytes`,
  `buffer_max_bytes`, `buffer_sampled_at`), and `dropping_since` once the stream's
  capacity-exhausted count rises past what it was when first sampled (new frames are being lost).
  Then it emits the gauges devops alerts on (`Cadence.Observability.Metrics.ReplayConflictMetrics`): open
  units per path, the oldest one's age, the tripped streams and their remaining room (each stream
  counted once), and the journal disk's free bytes. A failed sample is logged; the next one retries.
  """

  use GenServer

  require Logger

  alias Cadence.IngressJournal.FileSystem
  alias Cadence.Runtime.{Contacts, MissionRuntime}
  alias Cadence.Runtime.ReplayConflicts.{Recorder, Row}

  @interval_ms 10_000
  @paths ~w(storage processing timer)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @interval_ms)
    Process.send_after(self(), :sample, interval)
    {:ok, %{interval_ms: interval, snapshot: Keyword.get(opts, :snapshot, &snapshot/1)}}
  end

  @impl true
  def handle_info(:sample, state) do
    _ = sample_once(state.snapshot)
    Process.send_after(self(), :sample, state.interval_ms)
    {:noreply, state}
  end

  @doc """
  One sample. `snapshot` reads a stream's journal (`{:ok, %{retained_bytes, max_bytes, full_count}}`
  or anything else when it isn't running) from its open record.
  """
  @spec sample_once((Row.t() -> term()), DateTime.t()) :: :ok | :error
  def sample_once(snapshot \\ &snapshot/1, now \\ DateTime.utc_now()) do
    rows = Recorder.all_open()
    readings = rows |> Enum.filter(& &1.stream_key) |> read_streams(snapshot)
    Enum.each(rows, &put_reading(&1, Map.get(readings, &1.stream_key), now))
    emit(rows, readings, now)
    :ok
  rescue
    error ->
      Logger.warning("Stuck-processing sample failed: #{Exception.message(error)}")
      :error
  end

  # One journal read per stream, however many open records it has.
  defp read_streams(rows, snapshot) do
    rows
    |> Enum.uniq_by(& &1.stream_key)
    |> Enum.flat_map(fn row ->
      case snapshot.(row) do
        {:ok, %{retained_bytes: retained, max_bytes: max} = snap}
        when is_integer(retained) and is_integer(max) ->
          [{row.stream_key, %{retained: retained, max: max, full: Map.get(snap, :full_count, 0)}}]

        _not_running ->
          []
      end
    end)
    |> Map.new()
  end

  defp put_reading(_row, nil, _now), do: :ok

  defp put_reading(%Row{} = row, reading, now) do
    baseline = row.buffer_full_count || reading.full

    attrs = %{
      buffer_retained_bytes: reading.retained,
      buffer_max_bytes: reading.max,
      buffer_full_count: baseline,
      buffer_sampled_at: now,
      dropping_since: row.dropping_since || if(reading.full > baseline, do: now),
      updated_at: now
    }

    Recorder.put_buffer(row.id, attrs)
  end

  defp emit(rows, readings, now) do
    by_path = Enum.group_by(rows, & &1.path)

    for path <- @paths do
      open = Map.get(by_path, path, [])

      :telemetry.execute(
        [:cadence, :replay_id, :tripped],
        %{units: units(open), oldest_age_seconds: oldest_age(open, now)},
        %{path: path}
      )
    end

    :telemetry.execute(
      [:cadence, :replay_id, :tripped_streams],
      %{
        streams: map_size(readings),
        stream_headroom_bytes:
          readings |> Map.values() |> Enum.map(&max(&1.max - &1.retained, 0)) |> Enum.sum()
      },
      %{}
    )

    case Contacts.journal_volume() do
      {:ok, %{size_bytes: size, used_bytes: used}} ->
        :telemetry.execute(
          [:cadence, :ingress_journal, :disk],
          %{free_bytes: max(size - used, 0)},
          %{}
        )

      :unknown ->
        :ok
    end
  end

  defp units(rows), do: rows |> Enum.uniq_by(& &1.unit_key) |> length()

  defp oldest_age([], _now), do: 0

  defp oldest_age(rows, now),
    do: DateTime.diff(now, rows |> Enum.map(& &1.first_seen_at) |> Enum.min(DateTime), :second)

  defp snapshot(%Row{} = row) do
    row.mission_id
    |> MissionRuntime.provider_ingress_journal_name(
      row.realized_contact_id,
      row.path_id,
      row.provider_binding_id
    )
    |> FileSystem.snapshot()
  catch
    :exit, _reason -> :not_running
  end
end
