defmodule Cadence.ControllableRuntimePersistence do
  @moduledoc false

  use Agent

  def start_link(opts) do
    owner = Keyword.fetch!(opts, :owner)
    Agent.start_link(fn -> %{owner: owner, calls: []} end, name: __MODULE__)
  end

  def calls do
    Agent.get(__MODULE__, &Enum.reverse(&1.calls))
  end

  def persist_semantic_processing_results(processing_results, opts) do
    owner =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.owner, %{state | calls: [{processing_results, opts} | state.calls]}}
      end)

    ref = make_ref()
    send(owner, {:runtime_persistence_started, self(), ref, processing_results, opts})

    receive do
      {:release_runtime_persistence, ^ref} -> :ok
    end
  end
end
