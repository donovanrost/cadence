defmodule Cadence.Persistence.Retention.Rule do
  @moduledoc """
  One retention rule: what has aged out of one table, deleted a chunk at a time.

  A chunk runs in its own transaction, under a per-rule advisory lock so two nodes never sweep one
  rule at once. `sweep_chunk/3` returns whether more is left, how many rows it deleted, the cursor
  the next chunk resumes from, and a function the sweeper runs *after* the transaction commits (a
  file to remove: rows go first, so a crash leaves an orphan file, never an index row pointing at a
  missing one).
  """

  @type cursor :: term()
  @type chunk_result :: {:more | :done, non_neg_integer(), cursor(), (-> any())}

  @doc "The rule's name: its metric dimension and its advisory lock key."
  @callback name() :: atom()

  @doc "Whether this deployment has anything for the rule to sweep."
  @callback enabled?(settings :: keyword()) :: boolean()

  @doc "The cursor of a walk that starts from the beginning."
  @callback initial_cursor() :: cursor()

  @doc "How often to sweep, when the rule wants other than the shared `interval_ms`."
  @callback interval_ms(settings :: keyword()) :: pos_integer()

  @optional_callbacks interval_ms: 1

  @doc "Deletes one chunk of what has expired at `now`, inside the caller's transaction."
  @callback sweep_chunk(cursor(), now :: DateTime.t(), settings :: keyword()) :: chunk_result()
end
