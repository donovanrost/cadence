defmodule Cadence.Runtime.PartitionStreamKeys.RetentionTest do
  use Cadence.DataCase, async: false

  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.Repo
  alias Cadence.Runtime.PartitionStreamKeys
  alias Cadence.Runtime.PartitionStreamKeys.Retention, as: Rule

  @now ~U[2026-11-26 12:00:00Z]

  setup do
    saved = Application.get_env(:cadence, :retention)
    Application.put_env(:cadence, :retention, stream_key_margin_days: 7)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:cadence, :retention, saved),
        else: Application.delete_env(:cadence, :retention)
    end)

    %{mission: "mission-stream-keys-#{System.unique_integer([:positive])}"}
  end

  defp key(mission, stream, days_old) do
    inserted = @now |> DateTime.add(-days_old * 86_400, :second) |> DateTime.to_naive()

    %{rows: [[ordinal]]} =
      Repo.query!(
        "INSERT INTO partition_stream_keys (mission_id, partition_id, stream_key, inserted_at) VALUES ($1, 'p', $2, $3) RETURNING ordinal",
        [mission, stream, inserted]
      )

    ordinal
  end

  defp present?(ordinal),
    do:
      Repo.query!("SELECT 1 FROM partition_stream_keys WHERE ordinal = $1", [ordinal]).num_rows ==
        1

  defp sweep(opts \\ []),
    do: Sweeper.sweep(Rule, Rule.initial_cursor(), Keyword.merge([now: @now, pause_ms: 0], opts))

  test "a key past the replay horizon goes; one inside it survives", c do
    # Horizon: 30 d (archives) + 7 d margin = 37 d.
    old = key(c.mission, "stream-old", 40)
    inside = key(c.mission, "stream-inside", 36)
    fresh = key(c.mission, "stream-fresh", 0)

    assert %{stopped: :done, rows: rows} = sweep()
    assert rows >= 1

    refute present?(old)
    assert present?(inside)
    assert present?(fresh)
  end

  test "the horizon is derived from the archives' settings, not a number of its own", c do
    Application.put_env(:cadence, :retention, ingress_archive_days: 60, stream_key_margin_days: 7)
    # 60 + 7 = 67: a 50 day old key is still inside it, a 70 day old key is not.
    fifty = key(c.mission, "stream-50", 50)
    seventy = key(c.mission, "stream-70", 70)

    sweep()

    assert present?(fifty)
    refute present?(seventy)
  end

  test "the reserved timer and init keys survive however old they are", c do
    keys =
      for stream <- [
            PartitionStreamKeys.timer_stream(),
            PartitionStreamKeys.init_stream(),
            PartitionStreamKeys.timer_stream() <> ":capability-123",
            PartitionStreamKeys.init_stream() <> ":capability-123"
          ],
          do: key(c.mission, stream, 400)

    old = key(c.mission, "stream-ancient", 400)
    # A journal stream that merely starts with the word is a journal stream, not a reserved key.
    lookalike = key(c.mission, "timer-lookalike-stream", 400)

    sweep()

    assert Enum.all?(keys, &present?/1)
    refute present?(old)
    refute present?(lookalike)
  end

  test "it deletes in chunks of at most chunk_rows", c do
    ordinals = for n <- 1..7, do: key(c.mission, "stream-#{n}", 100)

    assert %{chunks: chunks, rows: rows, stopped: :done} = sweep(chunk_rows: 3)
    assert rows >= 7
    assert chunks >= 3
    refute Enum.any?(ordinals, &present?/1)
  end
end
