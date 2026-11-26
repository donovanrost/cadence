defmodule Cadence.Observability.ScaleSampler.Mailboxes do
  @moduledoc """
  Mailbox pressure for `Cadence.Observability.ScaleSampler` (#717): the busiest processes, and
  for each watched module the processes with a backlog and their sum and max. Grouping by the
  process's module covers singletons and per-mission processes alike (one archive writer and
  one coordinator per mission). Only processes with a non-empty mailbox are inspected. The
  watched modules come from the caller (`mix cadence.scale.run`): platform code names no domain
  module.
  """

  @doc "One second's mailbox line: `by_module` for `modules`, plus the `top` busiest processes."
  @spec sample([module()], non_neg_integer()) :: %{by_module: map(), top: [map()]}
  def sample(modules, top) do
    backlogged =
      Enum.flat_map(Process.list(), fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} when len > 0 -> [{pid, len}]
          _empty_or_gone -> []
        end
      end)

    %{by_module: by_module(backlogged, modules), top: busiest(backlogged, top)}
  end

  defp by_module(backlogged, modules) do
    empty = Map.new(modules, &{inspect(&1), %{processes: 0, sum: 0, max: 0}})

    Enum.reduce(backlogged, empty, fn {pid, len}, acc ->
      key = pid |> module() |> inspect()

      case acc do
        %{^key => %{processes: n, sum: sum, max: max}} ->
          Map.put(acc, key, %{processes: n + 1, sum: sum + len, max: Kernel.max(max, len)})

        _not_watched ->
          acc
      end
    end)
  end

  defp busiest(backlogged, top) do
    backlogged
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(top)
    |> Enum.map(fn {pid, len} ->
      %{process: label(pid), module: inspect(module(pid)), len: len}
    end)
  end

  defp module(pid) do
    case :proc_lib.translate_initial_call(pid) do
      {module, _function, _arity} -> module
      _unknown -> nil
    end
  end

  defp label(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) -> inspect(name)
      _unnamed -> inspect(pid)
    end
  end
end
