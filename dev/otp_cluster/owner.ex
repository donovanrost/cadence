defmodule Cadence.OTPClusterSpike.Owner do
  @moduledoc false
  use GenServer

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :transient}
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def route(key) do
    case :global.whereis_name(key) do
      :undefined -> {:error, :unavailable}
      pid -> GenServer.call(pid, :work, 1_000)
    end
  catch
    :exit, reason -> {:error, {:unknown_outcome, reason}}
  end

  @impl true
  def init(opts) do
    key = Keyword.fetch!(opts, :key)

    case :global.register_name(key, self(), &:global.random_notify_name/3) do
      :yes -> {:ok, %{key: key, ready?: Keyword.get(opts, :ready?, false)}}
      :no -> {:stop, {:shutdown, :name_taken}}
    end
  end

  @impl true
  def handle_call(:ready, _from, state), do: {:reply, :ok, %{state | ready?: true}}

  def handle_call(:work, _from, %{ready?: true} = state),
    do: {:reply, {:ok, node(), self()}, state}

  def handle_call(:work, _from, state), do: {:reply, {:error, :recovering}, state}

  @impl true
  def handle_info({:global_name_conflict, key}, %{key: key} = state),
    do: {:stop, {:shutdown, :name_conflict}, state}
end
