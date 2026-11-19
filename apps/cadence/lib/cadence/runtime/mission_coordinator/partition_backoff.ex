defmodule Cadence.Runtime.MissionCoordinator.PartitionBackoff do
  @moduledoc """
  Backoff for a partition whose owner fails to initialize.

  Partition owners start lazily on ingress and initialize after `start_child` returns, so a
  failed initialization isn't a supervisor restart: the very next frame used to start a new
  owner, acquire semantic ownership again (epoch + 1) and fail the same way, every ~15 ms
  (qa, 2026-11-11: spacecraft 005/006 while QuestDB hung). After a failure the partition isn't
  started again until its delay has passed: 250 ms doubling to 30 s, back to 250 ms after a
  quiet minute. Meanwhile routes to it fail fast with `{:partition_initialization_backoff,
  reason, retry_in_ms}`.
  """

  @initial_ms 250
  @max_ms 30_000
  @quiet_ms 60_000

  @type t :: %{optional(term()) => map()}

  @spec check(t(), term(), integer()) :: :ok | {:error, term()}
  def check(backoff, key, now_ms) do
    case Map.get(backoff, key) do
      %{until: until, reason: reason} when now_ms < until ->
        {:error, {:partition_initialization_backoff, reason, until - now_ms}}

      _clear ->
        :ok
    end
  end

  @spec failed(t(), term(), term(), integer()) :: {t(), pos_integer()}
  def failed(backoff, key, reason, now_ms) do
    delay =
      case Map.get(backoff, key) do
        %{delay: delay, at: at} when now_ms - at < delay + @quiet_ms -> min(delay * 2, @max_ms)
        _first -> @initial_ms
      end

    entry = %{delay: delay, at: now_ms, until: now_ms + delay, reason: reason}
    {Map.put(backoff, key, entry), delay}
  end
end
