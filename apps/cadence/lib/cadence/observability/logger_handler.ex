defmodule Cadence.Observability.LoggerHandler do
  @moduledoc false

  @behaviour :logger_handler

  @impl true
  def adding_handler(%{config: config} = handler_config) when is_map(config) do
    with {:ok, worker} <- Map.fetch(config, :worker),
         {:ok, max_queue} <- Map.fetch(config, :max_queue),
         true <- valid_worker?(worker),
         true <- is_integer(max_queue) and max_queue > 0 do
      {:ok, handler_config}
    else
      _invalid -> {:error, :invalid_config}
    end
  end

  @impl true
  def changing_config(_set_or_update, _old_config, new_config), do: adding_handler(new_config)

  @impl true
  def removing_handler(_handler_config), do: :ok

  @impl true
  def log(event, %{config: %{worker: worker, max_queue: max_queue}}) do
    case resolve_worker(worker) do
      pid when is_pid(pid) ->
        if mailbox_below_limit?(pid, max_queue) do
          send(pid, {:otel_log, event})
        end

      _missing ->
        :ok
    end

    :ok
  end

  defp valid_worker?(worker), do: is_pid(worker) or is_atom(worker)

  defp resolve_worker(worker) when is_pid(worker), do: worker
  defp resolve_worker(worker) when is_atom(worker), do: Process.whereis(worker)

  defp mailbox_below_limit?(pid, max_queue) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, queue_length} -> queue_length < max_queue
      nil -> false
    end
  end
end
