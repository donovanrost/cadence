defmodule Cadence.Commanding.ReleaseAttemptLock do
  @moduledoc """
  Serializes, per release attempt, the transactions that match transport evidence to its
  verifiers (DECISIONS #72).

  The release transaction inserts the attempt's verifier instances and then catches up from the
  transport records already stored; the runtime fact consumer evaluates newly committed records
  against the pending instances. Under READ COMMITTED each could miss the other's uncommitted
  rows, so a completion acknowledged within milliseconds of the send was never matched. Both take
  this lock before reading and hold it to commit: whichever runs second waits for the first to
  commit and then reads its rows.

  Locks are transaction-scoped and taken in one global order (mission, then attempt id), so
  callers holding several can't deadlock each other.
  """

  alias Ecto.Adapters.SQL

  @spec acquire(module(), binary(), [binary()]) :: :ok
  def acquire(repo, mission_id, release_attempt_ids)
      when is_binary(mission_id) and is_list(release_attempt_ids) do
    release_attempt_ids
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.each(
      &SQL.query!(repo, "SELECT pg_advisory_xact_lock($1::bigint)", [key(mission_id, &1)])
    )
  end

  @doc false
  @spec key(binary(), binary()) :: integer()
  def key(mission_id, release_attempt_id) do
    identity = :erlang.term_to_binary({__MODULE__, mission_id, release_attempt_id})
    <<key::signed-64, _rest::binary>> = :crypto.hash(:sha256, identity)
    key
  end
end
