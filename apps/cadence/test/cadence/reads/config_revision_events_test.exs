defmodule Cadence.Reads.ConfigRevisionEventsTest do
  @moduledoc "BACKLOG 8d: applied configuration revisions are Timeline `config` events."
  use Cadence.DataCase, async: false

  alias Cadence.Configuration.{Ledger, RevisionRow}
  alias Cadence.Reads.{EventLog, MissionTimeline}
  alias Cadence.Repo

  @org "org-config-revision-events"
  @mission "mission-config-revision-events"
  @at ~U[2026-11-12 10:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    # The baseline (r1) is created on first read; it never shows.
    Ledger.ensure_head(@org, @mission)
    revision(2, DateTime.add(@at, 60), kind: "change_set", entry_count: 2)
    revision(3, DateTime.add(@at, 120), kind: "rollback", rolls_back_to: 1, entry_count: 2)
    :ok
  end

  defp revision(number, applied_at, attrs) do
    Repo.insert!(%RevisionRow{
      revision_id: "config_revision-test-#{number}",
      organization_id: @org,
      mission_id: @mission,
      revision_number: number,
      kind: Keyword.fetch!(attrs, :kind),
      rolls_back_to: Keyword.get(attrs, :rolls_back_to),
      applied_by: %{"kind" => "user", "id" => "user-1", "name" => "Mira K."},
      applied_at: applied_at,
      reason: "test",
      summary: "test",
      entry_count: Keyword.get(attrs, :entry_count, 0)
    })
  end

  defp page(extra) do
    EventLog.page(
      @org,
      @mission,
      Map.merge(
        %{
          from: @at,
          to: DateTime.add(@at, 3_600),
          limit: 50,
          cursor: nil,
          kinds: nil,
          plane: nil,
          spacecraft_id: nil
        },
        extra
      )
    )
  end

  test "the event log lists applied and rolled-back revisions as config, newest first" do
    assert {:ok, %{events: [rollback, applied], next_cursor: nil}} = page(%{kinds: ["config"]})

    assert %{
             kind: "config",
             raw_kind: "config_revision_rolled_back",
             severity: :info,
             text: "Rolled back to r1",
             spacecraft: nil,
             refs: %{subject: %{kind: "config_revision", id: "3", name: "r3"}}
           } = rollback

    assert %{
             kind: "config",
             raw_kind: "config_revision_applied",
             text: "Applied r2 · 2 changes",
             refs: %{subject: %{kind: "config_revision", id: "2", name: "r2"}}
           } = applied

    assert applied.at == DateTime.add(@at, 60)
  end

  test "a revision row reads back by its id (U69 A8b permalink); the baseline doesn't" do
    {:ok, %{events: [rollback, applied]}} = page(%{kinds: ["config"]})

    assert {:ok, %{id: id, text: "Rolled back to r1"}} =
             EventLog.fetch(@org, @mission, rollback.id)

    assert id == rollback.id
    assert {:ok, %{text: "Applied r2 · 2 changes"}} = EventLog.fetch(@org, @mission, applied.id)

    baseline = String.replace(applied.id, ~r/:2$/, ":1")
    assert {:error, :event_not_found} = EventLog.fetch(@org, @mission, baseline)
  end

  test "mission-wide: a spacecraft filter, another kind, or a window without them leaves them out" do
    assert {:ok, %{events: []}} = page(%{spacecraft_id: "spacecraft-1"})
    assert {:ok, %{events: []}} = page(%{kinds: ["limit"]})
    assert {:ok, %{events: []}} = page(%{from: DateTime.add(@at, 121)})
    assert {:ok, %{events: [_applied]}} = page(%{to: DateTime.add(@at, 120)})
  end

  test "pages through the cursor without repeats" do
    assert {:ok, %{events: [first], next_cursor: cursor}} = page(%{limit: 1})
    assert cursor
    assert {:ok, %{events: [second]}} = page(%{limit: 1, cursor: cursor})
    assert [first.text, second.text] == ["Rolled back to r1", "Applied r2 · 2 changes"]
  end

  test "density counts them as info" do
    assert %{buckets: [%{info: 2}]} =
             EventLog.density(@org, @mission, %{
               from: @at,
               to: DateTime.add(@at, 3_600),
               bucket_s: 3_600,
               kinds: ["config"],
               plane: nil,
               spacecraft_id: nil
             })
  end

  test "other timeline readers don't get them unless they ask" do
    assert [] = MissionTimeline.list_for_mission(@org, @mission)
  end
end
