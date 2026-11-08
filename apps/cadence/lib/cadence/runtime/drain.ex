defmodule Cadence.Runtime.Drain do
  @moduledoc "Settles local ingress before its resources are stopped; performs no journal handoff."

  alias Cadence.IngressJournal.FileSystem
  alias Cadence.Runtime
  alias Cadence.Runtime.{ContactCoordinator, ProcessNamespace}

  def run(%ProcessNamespace{} = namespace) do
    contacts =
      registered(namespace, {:realized_contact_coordinator, :_, :_})

    with {:ok, settlements} <- parallel(contacts, &ContactCoordinator.quiesce/1),
         {:ok, journals} <-
           parallel(
             registered(namespace, {:provider_ingress_journal, :_, :_, :_, :_}),
             &FileSystem.seal/1
           ),
         {:ok, _missions} <-
           parallel(Runtime.running_mission_ids(namespace), &stop_mission(namespace, &1)) do
      {:ok, %{contacts: length(settlements), journals: journals}}
    end
  end

  defp stop_mission(namespace, mission) do
    case Runtime.stop_mission(namespace, mission) do
      :ok -> {:ok, mission}
      error -> error
    end
  end

  defp registered(namespace, key) do
    Registry.select(namespace.registry, [{{key, :"$1", :_}, [], [:"$1"]}])
  end

  defp parallel(items, fun) do
    items
    |> Task.async_stream(fun, max_concurrency: 16, timeout: :infinity)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, results} -> {:cont, {:ok, [result | results]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, {:drain_task_exit, reason}}}
    end)
  end
end
