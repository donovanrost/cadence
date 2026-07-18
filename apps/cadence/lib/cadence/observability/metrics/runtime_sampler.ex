defmodule Cadence.Observability.Metrics.RuntimeSampler do
  @moduledoc """
  Periodically samples BEAM and observability-pipeline health into OTLP metrics.
  """

  use GenServer

  alias Cadence.Observability.LogExporter
  alias Cadence.Observability.Metrics.Reporter

  @default_interval_ms 10_000
  @log_component_attributes %{
    "otel.component.name" => "cadence_log_exporter",
    "otel.component.type" => "otlp_http_log_exporter"
  }
  @metric_component_attributes %{
    "otel.component.name" => "cadence_metrics_reporter",
    "otel.component.type" => "otlp_http_metric_exporter"
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      log_exporter: Keyword.get(opts, :log_exporter, LogExporter),
      log_max_queue: Keyword.get(opts, :log_max_queue, 5_000),
      metrics_reporter: Keyword.get(opts, :metrics_reporter, Reporter),
      previous_log_status: nil,
      previous_metric_status: nil
    }

    send(self(), :sample)
    {:ok, state}
  end

  @impl true
  def handle_info(:sample, state) do
    schedule_sample(state.interval_ms)

    state =
      state
      |> sample_beam()
      |> sample_ingress_runtime()
      |> sample_log_exporter()
      |> sample_metrics_reporter()

    {:noreply, state}
  end

  defp sample_beam(state) do
    Enum.each(:erlang.memory(), fn {memory_type, bytes} ->
      record(state, "beam.memory.usage", bytes, %{"memory.type" => memory_type})
    end)

    record(state, "beam.process.count", :erlang.system_info(:process_count))
    record(state, "beam.process.limit", :erlang.system_info(:process_limit))
    record(state, "beam.port.count", :erlang.system_info(:port_count))
    record(state, "beam.port.limit", :erlang.system_info(:port_limit))
    record(state, "beam.scheduler.run_queue", :erlang.statistics(:run_queue))
    state
  end

  defp sample_log_exporter(state) do
    case safe_status(state.log_exporter, &LogExporter.status/1) do
      {:ok, status} ->
        record(
          state,
          "otel.sdk.processor.log.queue.size",
          status.queued_count,
          @log_component_attributes
        )

        record(
          state,
          "otel.sdk.processor.log.queue.capacity",
          state.log_max_queue,
          @log_component_attributes
        )

        record_delta(
          state,
          "otel.sdk.exporter.log.exported",
          status.sent_count,
          previous_value(state.previous_log_status, :sent_count),
          @log_component_attributes
        )

        record_delta(
          state,
          "otel.sdk.exporter.log.exported",
          status.failed_count + status.dropped_count,
          previous_sum(state.previous_log_status, [:failed_count, :dropped_count]),
          Map.put(@log_component_attributes, "error.type", "export_failed")
        )

        %{state | previous_log_status: status}

      :error ->
        state
    end
  end

  defp sample_ingress_runtime(state) do
    entries = runtime_registry_entries()

    executor_snapshots =
      entries
      |> Enum.filter(fn {key, _pid} -> match?({:provider_ingress_executor, _, _, _, _}, key) end)
      |> Enum.flat_map(fn {_key, pid} -> snapshot(pid) end)

    projector_snapshots =
      entries
      |> Enum.filter(fn {key, _pid} ->
        match?({:provider_persistence_projector, _, _, _, _}, key)
      end)
      |> Enum.flat_map(fn {_key, pid} -> snapshot(pid) end)

    record(state, "cadence.telemetry.ingress.executor.count", length(executor_snapshots))

    record(
      state,
      "cadence.telemetry.ingress.queue.depth",
      sum(executor_snapshots, :queue_depth),
      %{"downstream" => "executor"}
    )

    record(
      state,
      "cadence.telemetry.ingress.backpressure",
      Enum.count(executor_snapshots, & &1.backpressured?),
      %{"downstream" => "ingress_persistence_projector"}
    )

    record(
      state,
      "cadence.telemetry.ingress.capacity_waiter.count",
      sum(executor_snapshots, :capacity_waiter_count)
    )

    record(
      state,
      "cadence.telemetry.persistence.projector.count",
      length(projector_snapshots)
    )

    record(
      state,
      "cadence.telemetry.persistence.queue.depth",
      sum(projector_snapshots, :queue_depth)
    )

    record(
      state,
      "cadence.telemetry.persistence.capacity_waiter.count",
      sum(projector_snapshots, :capacity_waiter_count)
    )

    state
  end

  defp sample_metrics_reporter(state) do
    case safe_status(state.metrics_reporter, &Reporter.status/1) do
      {:ok, status} ->
        record(
          state,
          "otel.sdk.exporter.metric_data_point.inflight",
          status.series_count,
          @metric_component_attributes
        )

        record_delta(
          state,
          "otel.sdk.exporter.metric_data_point.exported",
          status.exported_data_point_count,
          previous_value(state.previous_metric_status, :exported_data_point_count),
          @metric_component_attributes
        )

        record_delta(
          state,
          "otel.sdk.exporter.metric_data_point.exported",
          status.failed_data_point_count + status.dropped_data_point_count,
          previous_sum(
            state.previous_metric_status,
            [:failed_data_point_count, :dropped_data_point_count]
          ),
          Map.put(@metric_component_attributes, "error.type", "export_failed")
        )

        %{state | previous_metric_status: status}

      :error ->
        state
    end
  end

  defp safe_status(server, status_fun) do
    case resolve_server(server) do
      pid when is_pid(pid) ->
        {:ok, status_fun.(pid)}

      nil ->
        :error
    end
  catch
    :exit, _reason -> :error
  end

  defp runtime_registry_entries do
    case Process.whereis(Cadence.Runtime.Registry) do
      pid when is_pid(pid) ->
        Registry.select(Cadence.Runtime.Registry, [
          {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
        ])

      nil ->
        []
    end
  end

  defp snapshot(pid) do
    case GenServer.call(pid, :snapshot, 100) do
      {:ok, snapshot} when is_map(snapshot) -> [snapshot]
      snapshot when is_map(snapshot) -> [snapshot]
      _unavailable -> []
    end
  catch
    :exit, _reason -> []
  end

  defp sum(snapshots, key) do
    Enum.reduce(snapshots, 0, &(Map.get(&1, key, 0) + &2))
  end

  defp resolve_server(server) when is_pid(server), do: server
  defp resolve_server(server) when is_atom(server), do: Process.whereis(server)

  defp record(state, name, value, attributes \\ %{}) do
    Reporter.record(state.metrics_reporter, name, value, attributes)
  end

  defp record_delta(state, name, current, previous, attributes) do
    delta = max(current - previous, 0)

    if delta > 0 do
      record(state, name, delta, attributes)
    end
  end

  defp previous_value(nil, _key), do: 0
  defp previous_value(status, key), do: Map.fetch!(status, key)

  defp previous_sum(nil, _keys), do: 0

  defp previous_sum(status, keys) do
    Enum.reduce(keys, 0, &(Map.fetch!(status, &1) + &2))
  end

  defp schedule_sample(interval_ms) do
    Process.send_after(self(), :sample, interval_ms)
  end
end
