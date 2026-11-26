defmodule Cadence.Protocol.RecordArchive.FileSystem.RetentionTest do
  use Cadence.DataCase, async: false
  @moduletag :tmp_dir

  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.Protocol.RecordArchive.FileSystem.Retention, as: Rule
  alias Cadence.Repo

  @now ~U[2026-11-26 12:00:00Z]

  setup %{tmp_dir: base} do
    saved =
      {Application.get_env(:cadence, :protocol_record_archive),
       Application.get_env(:cadence, :retention)}

    Application.put_env(:cadence, :protocol_record_archive,
      module: Cadence.Protocol.RecordArchive.FileSystem,
      base_path: base
    )

    Application.put_env(:cadence, :retention, protocol_archive_days: 30)

    on_exit(fn ->
      {archive, retention} = saved
      restore(:protocol_record_archive, archive)
      restore(:retention, retention)
    end)

    %{base: base, mission: "mission-protocol-retention-#{System.unique_integer([:positive])}"}
  end

  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)

  # A segment last receiving `days_old` days ago (its file under that day's directory) with
  # `identities` identity rows.
  defp segment(c, name, days_old, opts \\ []) do
    last = DateTime.add(@now, -days_old * 86_400, :second)
    first = DateTime.add(last, -60, :second)
    day = last |> DateTime.to_date() |> Date.to_iso8601()
    object_key = "#{c.mission}/#{day}/#{name}.bin"

    unless Keyword.get(opts, :no_file, false) do
      File.mkdir_p!(Path.dirname(Path.join(c.base, object_key)))
      File.write!(Path.join(c.base, object_key), "segment")
    end

    {1, [%{id: id}]} =
      Repo.insert_all(
        "protocol_archive_segments",
        [
          %{
            archive_backend: Keyword.get(opts, :backend, "filesystem"),
            mission_id: c.mission,
            object_key: object_key,
            packet_count: 2,
            frame_count: 1,
            first_receipt_time: first,
            last_receipt_time: last,
            inserted_at: DateTime.utc_now()
          }
        ],
        returning: [:id]
      )

    Repo.insert_all(
      "protocol_archive_record_identities",
      for n <- 1..3 do
        %{record_kind: "packet", record_id: "#{name}-#{n}", content_sha256: <<n>>, segment_id: id}
      end
    )

    object_key
  end

  # A file in a day directory that no segment row names.
  defp orphan(c, day, name) do
    key = "#{c.mission}/#{day}/#{name}.bin"
    File.mkdir_p!(Path.dirname(Path.join(c.base, key)))
    File.write!(Path.join(c.base, key), "orphan")
    key
  end

  defp rows_of(key) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM protocol_archive_segments WHERE object_key = $1", [key])

    count
  end

  defp identities(c),
    do:
      Repo.query!(
        """
        SELECT count(*) FROM protocol_archive_record_identities i
        JOIN protocol_archive_segments s ON s.id = i.segment_id WHERE s.mission_id = $1
        """,
        [c.mission]
      ).rows
      |> hd()
      |> hd()

  defp file?(c, key), do: File.exists?(Path.join(c.base, key))

  defp sweep(opts \\ []),
    do: Sweeper.sweep(Rule, Rule.initial_cursor(), Keyword.merge([now: @now, pause_ms: 0], opts))

  test "an expired segment's row, identities and file go; a newer segment is untouched", c do
    old = segment(c, "old", 40)
    fresh = segment(c, "fresh", 1)

    assert %{stopped: :done, rows: 1} = sweep()

    assert rows_of(old) == 0
    refute file?(c, old)
    assert rows_of(fresh) == 1
    assert file?(c, fresh)
    # Only the fresh segment's three identities remain: the cascade took the old one's.
    assert identities(c) == 3
  end

  test "a segment whose last record is inside the window keeps its row, identities and file", c do
    # Written across the cutoff: it began 31 days ago but its last record is 29 days old.
    straddling = segment(c, "straddle", 29)

    assert %{rows: 0} = sweep()
    assert rows_of(straddling) == 1
    assert file?(c, straddling)
    assert identities(c) == 3
  end

  test "it deletes in chunks of segments and tolerates a file that is already gone", c do
    keys = for n <- 1..5, do: segment(c, "chunked-#{n}", 40 + n)
    File.rm!(Path.join(c.base, hd(keys)))

    assert %{rows: 5, stopped: :done, chunks: chunks} = sweep(chunk_segments: 2)
    assert chunks >= 3
    assert Enum.all?(keys, &(rows_of(&1) == 0))
    refute Enum.any?(keys, &file?(c, &1))
    assert identities(c) == 0
  end

  test "another archive instance's segments are not swept", c do
    other = segment(c, "other-instance", 40, backend: "filesystem:b2xkZXI")

    assert %{rows: 0} = sweep()
    assert rows_of(other) == 1
    assert file?(c, other)
  end

  describe "orphan files" do
    test "an old file no segment row names goes; one with a row, and a recent one, stay", c do
      indexed = segment(c, "indexed", 29)
      lost = orphan(c, Date.to_iso8601(Date.add(~D[2026-11-26], -40)), "lost")
      # A day inside the margin of the cutoff (a segment's first entry may be a day earlier than
      # its day of last write): left alone even though no row names it.
      recent = orphan(c, Date.to_iso8601(Date.add(~D[2026-11-26], -30)), "recent")
      # An old directory with a segment row, whose file must stay.
      kept = segment(c, "kept-old-dir", 29)

      Repo.query!(
        "UPDATE protocol_archive_segments SET last_receipt_time = $1 WHERE object_key = $2",
        [
          NaiveDateTime.add(~N[2026-11-26 12:00:00], -29 * 86_400),
          kept
        ]
      )

      assert %{stopped: :done} = sweep()

      refute file?(c, lost)
      assert file?(c, recent)
      assert file?(c, indexed)
      assert file?(c, kept)
      # The day directory it left empty went with it.
      refute File.dir?(Path.dirname(Path.join(c.base, lost)))
    end

    test "the walk is chunked and resumes", c do
      day = Date.to_iso8601(Date.add(~D[2026-11-26], -45))
      lost = for n <- 1..5, do: orphan(c, day, "lost-#{n}")

      first = sweep(chunk_rows: 2, budget_ms: 0)
      assert first.stopped == :budget

      rest = Sweeper.sweep(Rule, first.cursor, now: @now, pause_ms: 0, chunk_rows: 2)
      assert rest.stopped == :done
      refute Enum.any?(lost, &file?(c, &1))
    end
  end

  test "it is on only for the filesystem archive with a path" do
    assert Rule.enabled?([])

    Application.put_env(:cadence, :protocol_record_archive,
      module: Cadence.Protocol.RecordArchive.Postgres
    )

    refute Rule.enabled?([])

    Application.put_env(:cadence, :protocol_record_archive,
      module: Cadence.Protocol.RecordArchive.FileSystem
    )

    refute Rule.enabled?([])
  end
end
