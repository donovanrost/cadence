defmodule Cadence.Commanding.VerifierScheduler do
  @moduledoc """
  Polling reconciler for command verifier timeouts.
  """

  use GenServer

  alias Cadence.Commanding

  @default_poll_interval_ms 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec reconcile_now(GenServer.server(), DateTime.t()) ::
          {:ok, [Cadence.Commanding.CommandVerifierInstance.t()]} | {:error, term()}
  def reconcile_now(server \\ __MODULE__, %DateTime{} = reference_time) do
    GenServer.call(server, {:reconcile_now, reference_time}, :infinity)
  end

  @impl true
  def init(opts) do
    state = %{
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      auto_schedule?: Keyword.get(opts, :auto_schedule?, true),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0)
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    maybe_reconcile_on_boot(state)
    schedule_next_reconcile(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:reconcile_now, %DateTime{} = reference_time}, _from, state) do
    {:reply, Commanding.timeout_command_verifier_instances(reference_time), state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    _ = Commanding.timeout_command_verifier_instances(resolve_reference_time(state))
    schedule_next_reconcile(state)
    {:noreply, state}
  end

  defp maybe_reconcile_on_boot(%{run_on_boot?: true} = state) do
    _ = Commanding.timeout_command_verifier_instances(resolve_reference_time(state))
    :ok
  end

  defp maybe_reconcile_on_boot(_state), do: :ok

  defp schedule_next_reconcile(%{auto_schedule?: true, poll_interval_ms: poll_interval_ms}) do
    Process.send_after(self(), :reconcile, poll_interval_ms)
  end

  defp schedule_next_reconcile(_state), do: :ok

  defp resolve_reference_time(state), do: state.reference_time_fun.()
end
