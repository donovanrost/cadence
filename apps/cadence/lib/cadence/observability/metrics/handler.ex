defmodule Cadence.Observability.Metrics.Handler do
  @moduledoc false

  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event_name, measurements, metadata, config) do
    with pid when is_pid(pid) <- resolve_worker(config.worker),
         {:message_queue_len, queue_length} <- Process.info(pid, :message_queue_len),
         true <- queue_length < config.max_queue do
      send(
        pid,
        {:otel_metric_event, event_name, measurements, metadata, System.system_time(:nanosecond)}
      )
    else
      _unavailable_or_full ->
        increment_drop_counter(config)
    end

    :ok
  end

  defp increment_drop_counter(%{drop_counter: counter}) do
    :atomics.add(counter, 1, 1)
    :ok
  end

  defp increment_drop_counter(_config), do: :ok

  defp resolve_worker(worker) when is_pid(worker), do: worker
  defp resolve_worker(worker) when is_atom(worker), do: Process.whereis(worker)
end
