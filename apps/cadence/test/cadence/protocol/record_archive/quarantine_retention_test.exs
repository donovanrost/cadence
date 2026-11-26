defmodule Cadence.Protocol.RecordArchive.Quarantine.RetentionTest do
  use Cadence.DataCase, async: false

  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.Protocol.RecordArchive.Quarantine
  alias Cadence.Protocol.RecordArchive.Quarantine.Retention, as: Rule
  alias Cadence.Repo

  @now ~U[2026-11-26 12:00:00.000000Z]
  # Protocol archive 30 days (the setup) + the 7-day review margin: an entry received more than
  # 37 days ago has expired.
  @days 37

  setup do
    saved = Application.get_env(:cadence, :retention)
    Application.put_env(:cadence, :retention, protocol_archive_days: 30)
    on_exit(fn -> restore(saved) end)

    mission = "mission-quarantine-retention-#{System.unique_integer([:positive])}"
    persist_mission_scope("org-#{mission}", mission)
    %{mission: mission}
  end

  defp restore(nil), do: Application.delete_env(:cadence, :retention)
  defp restore(value), do: Application.put_env(:cadence, :retention, value)

  defp ago(days), do: DateTime.add(@now, -days * 86_400 + 60, :second)

  # An entry whose record was received `days` ago (nil: no receipt time, first seen then).
  defp entry(c, id, days, opts \\ []) do
    at = ago(days)
    received? = Keyword.get(opts, :received?, true)

    {1, _} =
      Repo.insert_all("protocol_archive_quarantine", [
        %{
          quarantine_entry_id: "q-#{id}",
          mission_id: c.mission,
          organization_id: "org-#{c.mission}",
          realized_contact_id: Keyword.get(opts, :contact, "contact-1"),
          spacecraft_id: "sc-1",
          record_kind: Keyword.get(opts, :kind, "packet_record"),
          record_id: "record-#{id}",
          error_code: Keyword.get(opts, :code, "data_rejected"),
          error: "bad",
          entry: :erlang.term_to_binary(%{}),
          receipt_time: if(received?, do: at),
          first_seen_at: at,
          last_seen_at: at,
          inserted_at: at,
          updated_at: at
        }
      ])

    "q-#{id}"
  end

  defp resolution(c, id, days) do
    at = ago(days)

    {1, _} =
      Repo.insert_all("protocol_archive_quarantine_resolutions", [
        %{
          resolution_id: "r-#{id}",
          mission_id: c.mission,
          item_id: "contact-9:data_rejected",
          error_code: "data_rejected",
          action: "discarded",
          actor: %{"kind" => "user", "id" => "u"},
          counts: %{},
          resolved_at: at,
          inserted_at: at
        }
      ])
  end

  defp ids(table, column),
    do: Repo.all(from(r in table, select: field(r, ^column))) |> Enum.sort()

  defp entry_ids(c) do
    Repo.all(
      from(r in "protocol_archive_quarantine",
        where: r.mission_id == ^c.mission,
        select: r.quarantine_entry_id
      )
    )
    |> Enum.sort()
  end

  defp sweep(opts \\ []),
    do: Sweeper.sweep(Rule, Rule.initial_cursor(), Keyword.merge([now: @now, pause_ms: 0], opts))

  test "an entry goes when its record is older than the archive's retention plus the review margin",
       c do
    old = entry(c, "old", @days + 3)
    fresh = entry(c, "fresh", @days - 3)
    edge = entry(c, "edge", 1)

    assert %{stopped: :done} = sweep()
    assert entry_ids(c) == Enum.sort([fresh, edge])
    refute old in entry_ids(c)
  end

  test "without a receipt time the entry ages from its first sighting", c do
    old = entry(c, "old", @days + 3, received?: false)
    fresh = entry(c, "fresh", 2, received?: false)

    sweep()
    assert entry_ids(c) == [fresh]
    refute old in entry_ids(c)
  end

  test "the retention is the archive's and the margin is configurable", c do
    Application.put_env(:cadence, :retention,
      protocol_archive_days: 10,
      quarantine_review_days: 2
    )

    gone = entry(c, "gone", 13)
    kept = entry(c, "kept", 11)

    sweep()
    assert entry_ids(c) == [kept]
    refute gone in entry_ids(c)
  end

  test "an item closes as expired when its last entry goes, with a system resolution", c do
    entry(c, "a", @days + 5, contact: "contact-1")
    entry(c, "b", @days + 5, contact: "contact-1", kind: "transfer_frame_record")
    entry(c, "n", @days + 5, contact: nil, code: "identity_conflict")
    kept = entry(c, "k", 2, contact: "contact-2")

    sweep()

    assert entry_ids(c) == [kept]
    resolutions = Quarantine.resolutions_since(c.mission, DateTime.add(@now, -1, :hour))

    assert Enum.sort(Enum.map(resolutions, & &1.item_id)) == [
             "contact-1:data_rejected",
             "none:identity_conflict"
           ]

    assert Enum.all?(resolutions, &(&1.action == "expired" and &1.actor["kind"] == "system"))

    one = Enum.find(resolutions, &(&1.item_id == "contact-1:data_rejected"))
    assert one.counts == %{"entries" => 2, "frames" => 1, "packets" => 1}
    assert one.resolved_at == @now
  end

  test "an item that still has an entry is not resolved", c do
    entry(c, "old", @days + 5)
    entry(c, "fresh", 2)

    sweep()
    assert Quarantine.resolutions_since(c.mission, DateTime.add(@now, -1, :hour)) == []
    assert [_one] = entry_ids(c)
  end

  test "an item split across chunks resolves once, when its last chunk goes", c do
    for n <- 1..5, do: entry(c, "e#{n}", @days + 5)

    assert %{stopped: :done, chunks: chunks} = sweep(chunk_rows: 2)
    assert chunks >= 3
    assert entry_ids(c) == []

    assert [%{action: "expired", counts: %{"entries" => 1}}] =
             Quarantine.resolutions_since(c.mission, DateTime.add(@now, -1, :hour))
  end

  test "resolutions are kept their own time, then go", c do
    resolution(c, "old", 40)
    resolution(c, "fresh", 5)

    sweep()
    assert ids("protocol_archive_quarantine_resolutions", :resolution_id) == ["r-fresh"]
  end

  test "the attention item carries its expiry, then reads as expired", c do
    alias Cadence.Contacts.ArchiveQuarantineAttention, as: Attention
    org = "org-#{c.mission}"
    entry(c, "a", @days - 2)

    assert [%{expires_at: expires_at, state: "open"}] = Attention.items(org, c.mission)
    assert expires_at == DateTime.add(ago(@days - 2), 37 * 86_400, :second)

    # Two days on, the entry has expired: the item is gone and says why.
    later = DateTime.add(@now, 3 * 86_400, :second)
    Sweeper.sweep(Rule, Rule.initial_cursor(), now: later, pause_ms: 0)

    assert Attention.items(org, c.mission) == []

    assert [
             %{
               action: "expired",
               resolved_by: %{"kind" => "system"},
               id: "contact-1:data_rejected"
             }
           ] =
             Attention.resolved_since(org, c.mission, DateTime.add(later, -1, :hour))
  end

  test "the item's console expiry is when its last entry expires", c do
    entry(c, "a", 20)
    entry(c, "b", 10)
    rows = Quarantine.rows(c.mission)

    expected = DateTime.add(ago(10), 37 * 86_400, :second)
    assert Quarantine.expires_at(rows) == expected
  end

  test "it is on and named for the sweeper" do
    assert Rule.enabled?([])
    assert Rule.name() == :protocol_archive_quarantine
    assert Rule.initial_cursor() == nil
  end
end
