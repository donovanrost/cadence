defmodule Cadence.Projections.DataSources.Watermarks.RetentionTest do
  @moduledoc """
  #694 rule 3: the watermark event history is deleted by age in chunks; the status table and the
  event a status names stay.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.Projections.DataSources.Watermarks.Retention, as: Rule

  @now ~U[2026-11-26 12:00:00Z]

  setup do
    saved = Application.get_env(:cadence, :retention)
    Application.put_env(:cadence, :retention, watermark_event_days: 30)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:cadence, :retention, saved),
        else: Application.delete_env(:cadence, :retention)
    end)

    %{tag: "wmret#{System.unique_integer([:positive])}"}
  end

  defp sweep(opts \\ []),
    do: Sweeper.sweep(Rule, Rule.initial_cursor(), Keyword.merge([now: @now, pause_ms: 0], opts))

  defp event!(tag, name, days_old) do
    at = DateTime.add(@now, -days_old * 86_400, :second)
    id = "#{tag}-#{name}"

    Repo.insert_all("data_source_watermark_events", [
      %{
        source_watermark_event_id: id,
        source_watermark_key: "#{tag}-key",
        mission_id: "#{tag}-mission",
        logical_source: "telemetry",
        data_source_id: "#{tag}-ds",
        event_type: "observed",
        confidence: "best_effort",
        observed_at: at,
        payload: %{},
        inserted_at: at
      }
    ])

    id
  end

  defp status!(tag, event_id) do
    Repo.insert_all("data_source_watermark_statuses", [
      %{
        source_watermark_key: "#{tag}-key",
        source_watermark_event_id: event_id,
        mission_id: "#{tag}-mission",
        logical_source: "telemetry",
        data_source_id: "#{tag}-ds",
        event_type: "observed",
        confidence: "best_effort",
        observed_at: @now,
        last_seen_at: @now,
        payload: %{},
        inserted_at: @now,
        updated_at: @now
      }
    ])
  end

  defp present?(id) do
    Repo.exists?(
      from(e in "data_source_watermark_events", where: e.source_watermark_event_id == ^id)
    )
  end

  test "it deletes events past the window and keeps the rest", %{tag: tag} do
    gone = event!(tag, "old", 31)
    kept = event!(tag, "recent", 29)

    assert %{stopped: :done} = sweep()

    refute present?(gone)
    assert present?(kept)
  end

  test "it keeps the event a status names, however old, and the status itself", %{tag: tag} do
    current = event!(tag, "current", 90)
    gone = event!(tag, "superseded", 91)
    status!(tag, current)

    sweep()

    assert present?(current)
    refute present?(gone)

    assert Repo.exists?(
             from(s in "data_source_watermark_statuses",
               where: s.source_watermark_key == ^"#{tag}-key"
             )
           )
  end

  test "it walks in chunks and resumes", %{tag: tag} do
    ids = for n <- 1..5, do: event!(tag, "batch-#{n}", 40 + n)

    first = sweep(chunk_rows: 2, budget_ms: 0)
    assert %{rows: 2, stopped: :budget} = first

    assert %{rows: 3, stopped: :done} =
             Sweeper.sweep(Rule, first.cursor, now: @now, pause_ms: 0, chunk_rows: 2)

    refute Enum.any?(ids, &present?/1)
  end
end
