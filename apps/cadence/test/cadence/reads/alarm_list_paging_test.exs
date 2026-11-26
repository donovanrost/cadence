defmodule Cadence.Reads.AlarmListPagingTest do
  @moduledoc """
  The alarm list in pages (#794, #176): every page enriched, a cursor that survives change between
  pages, and the per-plane / per-point filters the sister-alarm views ask the server for.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Limits.Event
  alias Cadence.Limits.Store.{LatestStateRow, LimitEventRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.AlarmList
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @org "org-alarm-paging"
  @mission "mission-alarm-paging"
  @points ["HK.a", "HK.b", "HK.c", "HK.d", "HK.e"]

  # 90 spacecraft x 5 points = 450 active alarms, red when (craft + point) divides by 3, newest
  # receipt first by index.
  defp rows(spacecraft \\ 1..90) do
    now = DateTime.utc_now()

    for craft <- spacecraft, {point, p} <- Enum.with_index(@points) do
      id = "sc-#{String.pad_leading("#{craft}", 3, "0")}"

      %{
        limit_event_id: "ev-#{craft}-#{point}",
        mission_id: @mission,
        organization_id: @org,
        spacecraft_scope_id: id,
        spacecraft_id: id,
        point_id: point,
        point_name: point,
        source_sample_type: "telemetry_sample",
        sample_id: "sample-#{craft}-#{point}",
        limit_definition_id: "def-#{point}",
        limit_definition_version: 1,
        limit_set_name: "default",
        evaluated_value: JsonDocument.wrap_value(craft),
        limit_state: "high",
        normalized_state: if(rem(craft + p, 3) == 0, do: "red", else: "yellow"),
        violation: true,
        generation_time: ~U[2026-11-26 12:00:00.000000Z],
        receipt_time: DateTime.add(~U[2026-11-26 12:00:00.000000Z], craft * 5 + p, :second),
        provenance: %{},
        inserted_at: now,
        updated_at: now
      }
    end
  end

  # The latest states, and each alarm's one evaluation (its first crossing is its generation time).
  defp seed(rows \\ rows()) do
    for chunk <- Enum.chunk_every(rows, 500) do
      Repo.insert_all(LatestStateRow, chunk)

      events =
        Enum.map(chunk, &Map.drop(&1, [:spacecraft_scope_id, :updated_at]))

      Repo.insert_all(LimitEventRow, events)
    end
  end

  setup do
    persist_mission_scope(@org, @mission)
    seed()
    :ok
  end

  defp load(filters), do: AlarmList.load(@org, @mission, filters)

  defp walk(filters, pages \\ []) do
    {:ok, page} = load(filters)

    case page.next_cursor do
      nil -> Enum.reverse([page | pages])
      cursor -> walk(Map.put(filters, :cursor, cursor), [page | pages])
    end
  end

  # Queries a block runs, from the repo's telemetry.
  defp queries(fun) do
    ref = make_ref()
    me = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:cadence, :repo, :query],
      fn _event, _m, meta, _ -> send(me, {ref, meta.source}) end,
      nil
    )

    result = fun.()
    :telemetry.detach({__MODULE__, ref})
    {result, drain(ref, [])}
  end

  defp drain(ref, acc) do
    receive do
      {^ref, source} -> drain(ref, [source | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "pages cover every alarm once, in the list's order, with a total and a last page" do
    pages = walk(%{limit: 200})

    assert Enum.map(pages, &length(&1.alarms)) == [200, 200, 50]
    assert Enum.all?(pages, &(&1.total == 450))
    assert List.last(pages).next_cursor == nil

    alarms = Enum.flat_map(pages, & &1.alarms)
    assert length(Enum.uniq_by(alarms, & &1.id)) == 450

    # The list's order: severity, then newest receipt first.
    keys = Enum.map(alarms, &{&1.severity != :critical, -DateTime.to_unix(&1.receipt_time)})
    assert keys == Enum.sort(keys)
  end

  test "every page is enriched, not only the first 200" do
    pages = walk(%{limit: 200})
    alarms = Enum.flat_map(pages, & &1.alarms)

    assert Enum.all?(List.last(pages).alarms, &Map.has_key?(&1, :unit))
    assert Enum.all?(alarms, &(&1.first_crossed_at == &1.generation_time))
    assert Enum.all?(alarms, &is_struct(&1.first_crossed_at, DateTime))
  end

  test "a page costs a fixed number of queries, however many rows it holds" do
    {{:ok, small}, small_queries} = queries(fn -> load(%{limit: 5}) end)
    {{:ok, large}, large_queries} = queries(fn -> load(%{limit: 200}) end)

    assert length(small.alarms) == 5 and length(large.alarms) == 200
    assert small_queries == large_queries
    assert length(large_queries) <= 8

    IO.puts(
      "alarm page queries: #{length(large_queries)} #{inspect(Enum.frequencies(large_queries))}"
    )
  end

  test "the default page is 100 and the limit is bounded" do
    assert {:ok, %{alarms: page}} = load(%{})
    assert length(page) == 100
    assert {:ok, %{alarms: page}} = load(%{limit: 0})
    assert length(page) == 100
    assert {:ok, %{alarms: page}} = load(%{limit: 5})
    assert length(page) == 5
  end

  test "the summary counts the whole mission, whatever the page or filters" do
    {:ok, page} = load(%{limit: 5, point_id: "HK.a"})
    assert page.summary.active == 450
    assert page.total == 90
  end

  test "state and severity filters are in the query" do
    Repo.update_all(
      from(r in LatestStateRow, where: r.spacecraft_id == "sc-001"),
      set: [violation: false, normalized_state: "green"]
    )

    assert {:ok, %{total: 445}} = load(%{})
    assert {:ok, %{total: 5, alarms: nominal}} = load(%{state: "nominal"})
    assert Enum.all?(nominal, &(&1.spacecraft_id == "sc-001"))
    assert {:ok, %{total: 450}} = load(%{state: "all"})

    assert {:ok, %{total: critical}} = load(%{severity: "critical"})
    assert {:ok, %{total: caution}} = load(%{severity: "caution"})
    assert critical + caution == 445

    assert {:ok, %{total: 89}} = load(%{query: "hk.a"})
    assert {:ok, %{total: 0}} = load(%{query: "nothing-like-this"})
    assert {:ok, %{total: 5}} = load(%{spacecraft_id: "sc-002"})
  end

  test "a cursor survives alarms that clear or appear between pages" do
    {:ok, first} = load(%{limit: 200})
    seen = Enum.map(first.alarms, & &1.id)
    last = List.last(first.alarms)

    # Between the pages: the alarms of the first page's last spacecraft clear, and a spacecraft's
    # alarms appear, older than the cursor (newer ones sort into pages already read).
    Repo.delete_all(from(r in LatestStateRow, where: r.spacecraft_id == ^last.spacecraft_id))
    seed(rows(0..0))

    rest = walk(%{limit: 200, cursor: first.next_cursor}) |> Enum.flat_map(& &1.alarms)
    ids = Enum.map(rest, & &1.id)

    # Nothing already read repeats; nothing cleared is listed; the new alarms are reached.
    assert Enum.all?(ids, &(&1 not in seen))
    assert length(Enum.uniq(ids)) == length(ids)
    refute Enum.any?(rest, &(&1.spacecraft_id == last.spacecraft_id))
    # sc-000's two red alarms sort among the critical ones, behind the cursor: only its three
    # caution alarms are ahead of it.
    assert Enum.count(rest, &(&1.spacecraft_id == "sc-000")) == 3

    still_ahead =
      for r <- rows(),
          r.limit_event_id not in seen,
          r.spacecraft_id != last.spacecraft_id,
          do: r

    assert length(rest) == length(still_ahead) + 3
  end

  test "a cursor that isn't one is refused" do
    for bad <- ["nonsense", "!!", Base.url_encode64("not a term", padding: false)] do
      assert {:error, :invalid_cursor} = load(%{cursor: bad})
    end
  end

  describe "when an alarm entered its state" do
    alias Cadence.Limits.Store.AlarmPage

    defp event(craft, state, minute, id) do
      at = DateTime.add(~U[2026-11-26 12:00:00.000000Z], minute * 60, :second)

      {:ok, _} =
        %Event{
          limit_event_id: "hist-#{id}",
          mission_id: @mission,
          spacecraft_id: craft,
          point_id: "HK.hist",
          point_name: "HK.hist",
          source_sample_type: :telemetry_sample,
          sample_id: "hs-#{id}",
          limit_definition_id: "def-hist",
          limit_definition_version: 1,
          limit_set_name: "default",
          evaluated_value: minute,
          limit_state: :high,
          normalized_state: state,
          violation: state != :green,
          generation_time: at,
          receipt_time: at,
          provenance: %{}
        }
        |> LimitEventRow.changeset()
        |> Repo.insert()

      at
    end

    test "the first evaluation after the newest one of another state" do
      event("sc-h", :green, 0, 1)
      event("sc-h", :yellow, 1, 2)
      crossed = event("sc-h", :red, 2, 3)
      event("sc-h", :red, 3, 4)
      event("sc-h", :red, 4, 5)

      assert %{{"sc-h", "HK.hist"} => ^crossed} =
               AlarmPage.crossed_at(@mission, [{"sc-h", "HK.hist", "red"}])

      # Asked for a state the newest evaluation isn't in, it has not been in it: nothing.
      assert AlarmPage.crossed_at(@mission, [{"sc-h", "HK.hist", "yellow"}]) == %{}
      # A point that was never anything else: its first evaluation.
      first = event("sc-g", :red, 7, 6)
      event("sc-g", :red, 8, 7)

      assert %{{"sc-g", "HK.hist"} => ^first} =
               AlarmPage.crossed_at(@mission, [{"sc-g", "HK.hist", "red"}])
    end

    test "a page's alarms are one statement, with mission-scope alarms a second" do
      event("sc-h", :red, 1, 1)
      mission_at = event(nil, :yellow, 2, 2)

      {result, queries} =
        queries(fn ->
          AlarmPage.crossed_at(@mission, [{"sc-h", "HK.hist", "red"}, {nil, "HK.hist", "yellow"}])
        end)

      assert length(queries) == 2
      assert result[{nil, "HK.hist"}] == mission_at
    end
  end

  describe "sister alarms: same point, same plane, not me" do
    setup do
      persist_mission_scope(@org, @mission)

      for {craft, plane} <- [{3, 7}, {4, 7}, {5, 7}, {6, 8}] do
        id = "sc-00#{craft}"

        {:ok, _} =
          SpacecraftStore.persist_spacecraft(
            @org,
            Spacecraft.new(%{
              spacecraft_id: id,
              organization_id: @org,
              mission_id: @mission,
              display_name: id,
              metadata: %{"plane" => plane}
            })
          )
      end

      :ok
    end

    test "the plane's alarms on the point, excluding the spacecraft itself" do
      assert {:ok, page} = load(%{point_id: "HK.b", plane: 7, exclude_spacecraft_id: "sc-004"})
      assert Enum.map(page.alarms, & &1.spacecraft_id) |> Enum.sort() == ["sc-003", "sc-005"]
      assert page.total == 2
      assert Enum.all?(page.alarms, &(&1.point_id == "HK.b"))
    end

    test "a count is one row's page and the total" do
      assert {:ok, %{total: 3, alarms: [_one]}} = load(%{point_id: "HK.b", plane: 7, limit: 1})
    end

    test "a plane with no spacecraft matches nothing" do
      assert {:ok, %{total: 0, alarms: [], next_cursor: nil}} =
               load(%{point_id: "HK.b", plane: 99})
    end
  end
end
