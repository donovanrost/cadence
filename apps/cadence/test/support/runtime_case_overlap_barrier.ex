defmodule Cadence.TestSupport.RuntimeCaseOverlapBarrier do
  @moduledoc false

  use GenServer

  @timeout 15_000

  def await_ready(participant) when participant in [:primary, :peer] do
    GenServer.call(server(), {:await_ready, participant}, @timeout)
  end

  def await_primary_release, do: GenServer.call(server(), :await_primary_release, @timeout)
  def release_peer, do: GenServer.call(server(), :release_peer, @timeout)

  @impl true
  def init(:ok), do: {:ok, waiting_for_ready()}

  @impl true
  def handle_call({:await_ready, participant}, from, %{phase: :ready, ready: nil} = state) do
    {:noreply, %{state | ready: {participant, from}}}
  end

  def handle_call(
        {:await_ready, participant},
        _from,
        %{phase: :ready, ready: {participant, _waiting_from}} = state
      ) do
    {:reply, {:error, {:duplicate_participant, participant}}, state}
  end

  def handle_call(
        {:await_ready, participant},
        _from,
        %{phase: :ready, ready: {waiting_participant, waiting_from}}
      )
      when participant != waiting_participant do
    GenServer.reply(waiting_from, :ok)
    {:reply, :ok, %{phase: :primary_running, peer_waiter: nil}}
  end

  def handle_call(:await_primary_release, from, %{phase: :primary_running} = state) do
    {:noreply, %{state | peer_waiter: from}}
  end

  def handle_call(:await_primary_release, _from, %{phase: :primary_released}) do
    unregister_barrier()
    {:stop, :normal, :ok, waiting_for_ready()}
  end

  def handle_call(:release_peer, _from, %{phase: :primary_running, peer_waiter: nil}) do
    {:reply, :ok, %{phase: :primary_released}}
  end

  def handle_call(:release_peer, _from, %{
        phase: :primary_running,
        peer_waiter: peer_waiter
      }) do
    unregister_barrier()
    GenServer.reply(peer_waiter, :ok)
    {:stop, :normal, :ok, waiting_for_ready()}
  end

  defp server do
    case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp waiting_for_ready do
    %{phase: :ready, ready: nil}
  end

  defp unregister_barrier do
    true = Process.unregister(__MODULE__)
  end
end
