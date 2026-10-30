defmodule Cadence.Runtime.PartitionRouter do
  @moduledoc """
  Resolves an admitted partition through its mission controller, then sends work
  directly to that owner. A failed call has an unknown outcome and is never
  retried here; journal callers retain their ordered replay responsibility.
  """

  def call(coordinator, key, request) do
    case reserve(coordinator, key) do
      {:ok, controller, owner, permit} ->
        try do
          GenServer.call(owner, request, :infinity)
        catch
          :exit, reason -> {:error, {:partition_outcome_unknown, reason}}
        after
          GenServer.cast(controller, {:release_partition_route, permit})
        end

      error ->
        error
    end
  end

  defp reserve(coordinator, key) do
    case GenServer.whereis(coordinator) do
      nil ->
        {:error, :mission_runtime_not_running}

      controller ->
        case GenServer.call(controller, {:partition_route, key}, :infinity) do
          {:ok, owner, permit} -> {:ok, controller, owner, permit}
          error -> error
        end
    end
  catch
    :exit, reason -> {:error, {:partition_route_unavailable, reason}}
  end
end
