defmodule Cadence.IngressArchive.RetentionTest do
  use Cadence.DataCase, async: false
  @moduletag :tmp_dir

  alias Cadence.IngressArchive.Retention, as: Rule
  alias Cadence.Persistence.Retention.Sweeper
  alias Cadence.Repo

  @now ~U[2026-11-26 12:00:00Z]

  setup %{tmp_dir: base} do
    saved =
      {Application.get_env(:cadence, :ingress_archive), Application.get_env(:cadence, :retention)}

    Application.put_env(:cadence, :ingress_archive, base_path: base)
    Application.put_env(:cadence, :retention, ingress_archive_days: 30)

    on_exit(fn ->
      {archive, retention} = saved

      if archive,
        do: Application.put_env(:cadence, :ingress_archive, archive),
        else: Application.delete_env(:cadence, :ingress_archive)

      if retention,
        do: Application.put_env(:cadence, :retention, retention),
        else: Application.delete_env(:cadence, :retention)
    end)

    %{base: base, mission: "mission-ingress-retention-#{System.unique_integer([:positive])}"}
  end

  # A segment: `count` evidence rows at `days_old` (the first at `days_old`, the others seconds
  # after), and its file.
  defp segment(c, name, days_old, opts \\ []) do
    object_key = "#{c.mission}/#{name}.bin"
    File.mkdir_p!(Path.dirname(Path.join(c.base, object_key)))
    File.write!(Path.join(c.base, object_key), "segment")

    rows =
      for n <- 1..Keyword.get(opts, :count, 3) do
        at =
          @now
          |> DateTime.add(
            -days_old * 86_400 + (n - 1) +
              Keyword.get(opts, :skew_last, 0) * if(n == 3, do: 1, else: 0),
            :second
          )

        %{
          evidence_id: "#{name}-#{n}",
          segment_id: name,
          object_key: object_key,
          archive_backend: Keyword.get(opts, :backend, "filesystem"),
          mission_id: c.mission,
          protocol_family: "tm",
          direction: "downlink",
          receipt_time: at,
          raw_size_bytes: 4,
          metadata: %{},
          inserted_at: DateTime.utc_now()
        }
      end

    {_count, _} = Repo.insert_all("ingress_archive_evidence_entries", rows)
    object_key
  end

  defp rows_of(key),
    do:
      Repo.query!("SELECT count(*) FROM ingress_archive_evidence_entries WHERE object_key = $1", [
        key
      ]).rows
      |> hd()
      |> hd()

  defp file?(c, key), do: File.exists?(Path.join(c.base, key))

  defp sweep(opts),
    do: Sweeper.sweep(Rule, Rule.initial_cursor(), Keyword.merge([now: @now, pause_ms: 0], opts))

  test "an expired segment's rows and file go; a newer segment is untouched", c do
    old = segment(c, "old", 40)
    fresh = segment(c, "fresh", 1)

    assert %{stopped: :done, rows: 3} = sweep([])

    assert rows_of(old) == 0
    refute file?(c, old)
    assert rows_of(fresh) == 3
    assert file?(c, fresh)
  end

  test "a segment that straddles the cutoff keeps its rows and its file", c do
    # Two rows expired, the last (skewed forward a day) not: the segment is not wholly expired.
    straddling = segment(c, "straddle", 30, skew_last: 3 * 86_400)

    assert %{rows: 0} = sweep([])

    assert rows_of(straddling) == 3
    assert file?(c, straddling)
  end

  test "it works in chunks of whole segments and tolerates a file that is already gone", c do
    keys = for n <- 1..5, do: segment(c, "chunked-#{n}", 40 + n)
    File.rm!(Path.join(c.base, hd(keys)))

    assert %{chunks: chunks, rows: 15, stopped: :done} = sweep(chunk_segments: 2)
    assert chunks >= 3
    assert Enum.all?(keys, &(rows_of(&1) == 0))
    refute Enum.any?(keys, &file?(c, &1))
  end

  test "another archive instance's rows are not swept", c do
    other = segment(c, "other-instance", 40, backend: "filesystem:b2xkZXI")

    assert %{rows: 0} = sweep([])
    assert rows_of(other) == 3
    assert file?(c, other)
  end

  test "it is off without a configured archive path" do
    Application.delete_env(:cadence, :ingress_archive)
    refute Rule.enabled?([])
  end
end
