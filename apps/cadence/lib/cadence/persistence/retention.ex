defmodule Cadence.Persistence.Retention do
  @moduledoc """
  Retention for the tables nothing else cleans (#694): the settings every rule shares, and the
  list of rules a node sweeps.

  A rule (`Cadence.Persistence.Retention.Rule`) deletes what has aged out of one table, a chunk at
  a time; a `Retention.Sweeper` runs it on a timer. Chunking is what protects ingest: every chunk
  is its own short transaction, so no lock outlives it, and a rule never waits for a quiet moment
  (at 500 spacecraft some pass is always near).

  Settings (`config :cadence, :retention`), with the platform defaults:

    * `enabled?` (true): off for tests;
    * `chunk_rows` (2,000) and `chunk_segments` (40): the size of one chunk of a row table or of
      an archive (rows or whole segments);
    * `pause_ms` (100): between chunks; `budget_ms` (60,000): the most one sweep runs; and
      `interval_ms` (600,000): between sweeps;
    * `ingress_archive_days`, `protocol_archive_days` and `watermark_event_days`: how long the
      archives keep what they index and how long the watermark history is kept; all default to the
      observation retention, so the stores can't drift apart;
    * `stream_key_margin_days` (7): added to the replay horizon below;
    * `identity_state_settlement_allowance_hours` (24) and `identity_state_interval_ms` (1 h): the
      identity-state rule (`Cadence.Telemetry.Storage.ObservationIdentityStates.Retention`).

  The observation retention is `:telemetry_observation_retention`'s `retention_days` (30), the
  same setting QuestDB's day-partition retention uses.

  **The replay horizon** is the longest window a journal stream can still be replayed from: the
  longest of the ingress archive's, the protocol archive's and the journal's own retention
  (`:ingress_journal`'s `completed_stream_retention_ms`, 72 h), plus the margin. A partition
  stream key may only be deleted after it (`Cadence.Runtime.PartitionStreamKeys.Retention`),
  because a replay of a stream whose key was deleted would allocate a new ordinal and give its
  effects new ids. It is computed from these same settings, never a separate number.
  """

  @defaults [
    enabled?: true,
    chunk_rows: 2_000,
    chunk_segments: 40,
    pause_ms: 100,
    budget_ms: 60_000,
    interval_ms: 600_000,
    stream_key_margin_days: 7,
    identity_state_settlement_allowance_hours: 24,
    identity_state_interval_ms: 3_600_000
  ]

  @default_observation_days 30
  @default_journal_ms 72 * 60 * 60 * 1000
  @day_ms 86_400_000

  @doc "The settings, with the platform defaults."
  @spec settings() :: keyword()
  def settings, do: Keyword.merge(@defaults, Application.get_env(:cadence, :retention, []))

  @doc "How long the observation store keeps observations: the one retention the others follow."
  @spec observation_days() :: pos_integer()
  def observation_days do
    :cadence
    |> Application.get_env(:telemetry_observation_retention, [])
    |> Keyword.get(:retention_days, @default_observation_days)
  end

  @doc "How long the ingress archive keeps what it indexes."
  @spec ingress_archive_days(keyword()) :: pos_integer()
  def ingress_archive_days(settings \\ settings()),
    do: Keyword.get(settings, :ingress_archive_days) || observation_days()

  @doc "How long the protocol archive keeps what it indexes."
  @spec protocol_archive_days(keyword()) :: pos_integer()
  def protocol_archive_days(settings \\ settings()),
    do: Keyword.get(settings, :protocol_archive_days) || observation_days()

  @doc "How long the watermark event history is kept."
  @spec watermark_event_days(keyword()) :: pos_integer()
  def watermark_event_days(settings \\ settings()),
    do: Keyword.get(settings, :watermark_event_days) || observation_days()

  @doc "How long the journal keeps a settled stream, in milliseconds."
  @spec journal_retention_ms() :: pos_integer()
  def journal_retention_ms do
    :cadence
    |> Application.get_env(:ingress_journal, [])
    |> Map.new()
    |> Map.get(:completed_stream_retention_ms, @default_journal_ms)
  end

  @doc "How long the journal keeps a settled stream, in whole days (rounded up)."
  @spec journal_days() :: pos_integer()
  def journal_days, do: max(div(journal_retention_ms() + @day_ms - 1, @day_ms), 1)

  @doc "How many days a journal stream can still be replayed from, plus the margin."
  @spec replay_horizon_days(keyword()) :: pos_integer()
  def replay_horizon_days(settings \\ settings()) do
    Enum.max([
      ingress_archive_days(settings),
      protocol_archive_days(settings),
      journal_days()
    ]) + Keyword.fetch!(settings, :stream_key_margin_days)
  end

  @doc "The instant `days` before `now`."
  @spec cutoff(DateTime.t(), pos_integer()) :: DateTime.t()
  def cutoff(%DateTime{} = now, days), do: DateTime.add(now, -days * 86_400, :second)

  @doc """
  Child specs for the sweepers of the enabled `rules` (none when retention is off). The rules
  belong to their own planes, so the composition root names them (`Cadence.Application`).
  """
  @spec children([module()], keyword()) :: [Supervisor.child_spec()]
  def children(rules, settings \\ settings()) do
    if Keyword.fetch!(settings, :enabled?) do
      for rule <- rules, rule.enabled?(settings) do
        {Cadence.Persistence.Retention.Sweeper, rule: rule}
      end
    else
      []
    end
  end
end
