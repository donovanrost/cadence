defmodule Cadence.Platform.SnapshotCall do
  @moduledoc """
  A read-only snapshot call that never takes its caller down (#334).

  A runtime's snapshot is a chain of synchronous reads:
  - a contact's `path_snapshot`;
  - its path coordinator's snapshot;
  - each provider runtime's snapshot;
  - each ingress executor's, projector's, journal's and consumer's.

  An uncaught `GenServer.call` timeout anywhere in that chain exits the process making it. A busy
  projector therefore terminated the LIVE TCP provider runtime that only asked for its counters.
  This call turns any exit into an `{:error, reason}` the caller reports as that part being
  unavailable:
  - `:snapshot_timeout`: the server was busy past the timeout;
  - `:not_running`: it's gone;
  - `:snapshot_failed`: anything else (the reason is logged, not returned).

  Timeouts shrink inward, so an inner read gives up before the read above it:
  - 500 ms for an executor's, projector's, journal's or consumer's snapshot;
  - 1 000 ms for a transport runtime's;
  - 3 000 ms for a provider runtime's;
  - 4 500 ms for a path coordinator's;
  - 5 000 ms for a contact's.

  The TCP receiver's flow-control read of its executor's queue depth uses `:flow_control`
  (5 000 ms, develop's wait), so a slow-but-alive executor doesn't stall downlink reads.

  A late reply is dropped by the runtime (calls use process aliases), so a caller that gave up
  gets no stray message.
  """

  @timeouts %{
    # Not a read in the inward chain: the TCP receiver's flow control asks the executor for its
    # queue depth before every recv (journal off), and a slow-but-alive executor must not stall
    # downlink reads, so it keeps develop's 5 s, with the exit still caught (fe-ops' review).
    flow_control: 5_000,
    component: 500,
    transport: 1_000,
    provider: 3_000,
    path: 4_500,
    contact: 5_000
  }

  @type level :: :flow_control | :component | :transport | :provider | :path | :contact

  require Logger

  @doc "This level's timeout in milliseconds (see the moduledoc)."
  @spec timeout(level()) :: pos_integer()
  def timeout(level), do: Map.fetch!(@timeouts, level)

  @doc "`GenServer.call(server, request, timeout(level))`, with every exit returned as an error."
  @spec call(GenServer.server(), term(), level()) :: term() | {:error, atom()}
  def call(server, request, level) do
    GenServer.call(server, request, timeout(level))
  catch
    :exit, {:timeout, _call} ->
      {:error, :snapshot_timeout}

    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] ->
      {:error, :not_running}

    :exit, {{:shutdown, _detail}, _call} ->
      {:error, :not_running}

    :exit, {:nodedown, _call} ->
      {:error, :not_running}

    :exit, reason ->
      # The raw exit reason stays in the log, never in the answer: callers may render a non-atom
      # reason into a REST body (ca-security's review).
      Logger.warning("snapshot call failed: #{inspect(reason)}")
      {:error, :snapshot_failed}
  end
end
