defmodule Cadence.Procedures.Dag.CancellationToken do
  @moduledoc """
  Lock-free cancellation token for DAG execution control signals.

  Uses Erlang's `:atomics` for thread-safe signal propagation without
  message passing delays. This eliminates the race condition between
  signal send and signal check that exists with message-based approaches.

  ## Why Atomics?

  The original implementation used `send/2` to forward control signals
  to the DAG executor Task. The executor would then check for signals
  via `receive after 0` between steps. This created a race window:

      ExecutionProcess                    DAG Executor Task
           |                                    |
           |-- send(:pause) ------------------>|
           |                                    | (in middle of step)
           |                                    | step completes
           |                                    | starts next step  <- RACE!
           |                                    | check_control_signals()
           |                                    | sees :pause

  With atomics, the signal is immediately visible:

      ExecutionProcess                    DAG Executor Task
           |                                    |
           |-- atomics.put(:pause) ----------->|
           |                                    | (in middle of step)
           |                                    | step completes
           |                                    | atomics.get() == :pause
           |                                    | stops immediately

  ## Usage

      # Create a token
      token = CancellationToken.new()

      # Pass to executor
      Executor.execute(steps, step_executor, context, cancellation_token: token)

      # Signal from another process
      CancellationToken.request_pause(token)  # or request_abort(token)

      # Check in executor (typically before starting each step)
      case CancellationToken.check(token) do
        :none -> # continue execution
        :pause -> # pause at safe point
        :abort -> # abort immediately
      end

  ## Signal Precedence

  Abort takes precedence over pause. If both are requested, abort wins.
  This ensures that abort is always respected even if pause was requested first.
  """

  # Signal values stored in atomics
  @none 0
  @pause 1
  @abort 2

  @type t :: %__MODULE__{ref: :atomics.atomics_ref()}

  defstruct [:ref]

  @doc """
  Creates a new cancellation token.

  The token starts in the `:none` state with no signal.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{ref: :atomics.new(1, signed: false)}
  end

  @doc """
  Requests a pause at the next safe point.

  Returns `:ok` if the pause signal was set, or `:already_signaled` if
  there's already a signal pending (pause or abort).

  ## Example

      case CancellationToken.request_pause(token) do
        :ok -> # pause will happen at next check
        :already_signaled -> # another signal already pending
      end
  """
  @spec request_pause(t()) :: :ok | :already_signaled
  def request_pause(%__MODULE__{ref: ref}) do
    case :atomics.compare_exchange(ref, 1, @none, @pause) do
      :ok -> :ok
      _ -> :already_signaled
    end
  end

  @doc """
  Requests an immediate abort.

  Unlike pause, abort always succeeds because it has the highest priority.
  It will override any existing pause signal.

  ## Example

      :ok = CancellationToken.request_abort(token)
  """
  @spec request_abort(t()) :: :ok
  def request_abort(%__MODULE__{ref: ref}) do
    :atomics.put(ref, 1, @abort)
    :ok
  end

  @doc """
  Clears any pending signal.

  Used when resuming execution after a pause.

  ## Example

      :ok = CancellationToken.clear(token)
  """
  @spec clear(t()) :: :ok
  def clear(%__MODULE__{ref: ref}) do
    :atomics.put(ref, 1, @none)
    :ok
  end

  @doc """
  Checks the current signal state.

  Returns one of:
  - `:none` - No signal pending, continue execution
  - `:pause` - Pause requested, stop at next safe point
  - `:abort` - Abort requested, stop immediately

  ## Example

      case CancellationToken.check(token) do
        :none -> start_next_step()
        :pause -> pause_execution()
        :abort -> abort_execution()
      end
  """
  @spec check(t()) :: :none | :pause | :abort
  def check(%__MODULE__{ref: ref}) do
    case :atomics.get(ref, 1) do
      @none -> :none
      @pause -> :pause
      @abort -> :abort
    end
  end

  @doc """
  Returns true if any signal (pause or abort) is pending.

  This is a convenience function for checking if execution should stop
  before starting a new step.

  ## Example

      unless CancellationToken.signaled?(token) do
        start_next_step()
      end
  """
  @spec signaled?(t()) :: boolean()
  def signaled?(%__MODULE__{ref: ref}) do
    :atomics.get(ref, 1) != @none
  end

  @doc """
  Returns true if a pause signal is pending.
  """
  @spec pause_requested?(t()) :: boolean()
  def pause_requested?(%__MODULE__{ref: ref}) do
    :atomics.get(ref, 1) == @pause
  end

  @doc """
  Returns true if an abort signal is pending.
  """
  @spec abort_requested?(t()) :: boolean()
  def abort_requested?(%__MODULE__{ref: ref}) do
    :atomics.get(ref, 1) == @abort
  end
end
