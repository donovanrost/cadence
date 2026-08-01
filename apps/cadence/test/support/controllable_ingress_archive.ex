defmodule Cadence.ControllableIngressArchive do
  @moduledoc false

  use Agent

  alias Cadence.IngressArchive.{Batch, Receipt}

  def start_link(opts \\ []) do
    Agent.start_link(fn -> initial_state(opts) end, name: __MODULE__)
  end

  def reset(opts \\ []) do
    Agent.update(__MODULE__, fn _state -> initial_state(opts) end)
  end

  def set_completion(completion) when completion in [:durable, :accepted] do
    Agent.update(__MODULE__, &Map.put(&1, :completion, completion))
  end

  def calls do
    Agent.get(__MODULE__, &Enum.reverse(&1.calls))
  end

  def persist_batch(%Batch{} = batch) do
    Agent.get_and_update(__MODULE__, fn state ->
      next_state = %{state | calls: [batch | state.calls]}

      if state.failures_remaining > 0 do
        {{:error, :injected_archive_failure},
         %{next_state | failures_remaining: state.failures_remaining - 1}}
      else
        {{:ok, Receipt.for_batch(batch, state.completion)}, next_state}
      end
    end)
  end

  defp initial_state(opts) do
    %{
      completion: Keyword.get(opts, :completion, :durable),
      failures_remaining: Keyword.get(opts, :failures_remaining, 0),
      calls: []
    }
  end
end
