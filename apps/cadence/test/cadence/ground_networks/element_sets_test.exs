defmodule Cadence.GroundNetworks.ElementSetsTest do
  use Cadence.DataCase, async: true

  alias Cadence.GroundNetworks.{ElementSet, ElementSets}
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow

  @actor %{"actor_kind" => "user", "user_id" => "user-element-sets"}
  @opts [actor: @actor, source: "manual"]

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-element-sets-#{suffix}"
    mission_id = "mission-element-sets-#{suffix}"
    persist_mission_scope(organization_id, mission_id)
    [craft] = insert_spacecraft!(organization_id, mission_id, 1)
    %{org: organization_id, mission: mission_id, craft: craft}
  end

  test "stores a set, answers a re-send with the stored row and keeps history", c do
    item = %{spacecraft_id: c.craft, input: {:tle, tle(1, 100.0)}}

    assert {:ok, [{:created, %ElementSet{} = first}]} = submit(c, [item])
    assert first.source == "manual" and first.format == "tle" and first.created_by == @actor
    assert {:ok, [{:unchanged, ^first}]} = submit(c, [item])

    newer = %{spacecraft_id: c.craft, input: {:tle, tle(2, 101.0)}}
    older = %{spacecraft_id: c.craft, input: {:tle, tle(0, 99.0)}}
    assert {:ok, [{:created, second}, {:created, _older}]} = submit(c, [newer, older])

    # The current set is the newest epoch, not the latest received.
    assert %ElementSet{element_set_id: id} = ElementSets.current(c.org, c.mission, c.craft)
    assert id == second.element_set_id
    assert Repo.aggregate(ElementSets.ElementSetRow, :count) == 3
  end

  test "answers each item on its own: refusals, unknown spacecraft and repeats", c do
    good = %{spacecraft_id: c.craft, input: {:tle, tle(1, 100.0)}}

    assert {:ok,
            [
              {:created, row},
              {:unchanged, row},
              {:refused, :spacecraft_not_found, %{spacecraft_id: "craft-missing"}},
              {:refused, :unparseable, %{field: "tle"}}
            ]} =
             submit(c, [
               good,
               good,
               %{good | spacecraft_id: "craft-missing"},
               %{good | input: {:tle, "garbage"}}
             ])

    assert Repo.aggregate(ElementSets.ElementSetRow, :count) == 1
    assert {:error, :empty_batch} = submit(c, [])
    assert {:error, :batch_too_large} = submit(c, List.duplicate(good, 1_001))
  end

  test "pages history newest epoch first without repeats or gaps", c do
    items = for day <- 1..5, do: %{spacecraft_id: c.craft, input: {:tle, tle(day, 100.0)}}
    assert {:ok, results} = submit(c, items)
    expected = results |> Enum.map(fn {:created, row} -> row end) |> Enum.reverse()

    {:ok, %{items: page1, next_cursor: cursor}} =
      ElementSets.history(c.org, c.mission, c.craft, nil, 2)

    {:ok, %{items: page2, next_cursor: cursor2}} =
      ElementSets.history(c.org, c.mission, c.craft, cursor, 2)

    {:ok, %{items: page3, next_cursor: nil}} =
      ElementSets.history(c.org, c.mission, c.craft, cursor2, 2)

    assert ids(page1 ++ page2 ++ page3) == ids(expected)
    assert {:error, :invalid_cursor} = ElementSets.history(c.org, c.mission, c.craft, "nope", 2)
    assert ElementSets.current(c.org, c.mission, "craft-other") == nil
  end

  test "stores 1,000 spacecraft's sets in one call with a bounded number of queries", c do
    crafts = insert_spacecraft!(c.org, c.mission, 1_000)

    items =
      for {craft, i} <- Enum.with_index(crafts),
          do: %{spacecraft_id: craft, input: {:tle, tle(1, i * 0.36)}}

    {queries, {:ok, results}} = count_queries(fn -> submit(c, items) end)

    assert length(results) == 1_000
    assert Enum.all?(results, &match?({:created, _}, &1))
    # Spacecraft in batches of 100, stored keys in one query, inserts in batches of 500, the
    # newest-epoch lookup and the one staged recompute job (#891), and the transaction's begin and
    # commit.
    # Constant in fleet size: lookups, inserts, and one staged recompute job and one staged
    # ephemeris-upload job (#968) for the whole batch.
    assert queries <= 19, "#{queries} queries"

    {queries, {:ok, again}} = count_queries(fn -> submit(c, items) end)
    assert Enum.all?(again, &match?({:unchanged, _}, &1))
    assert queries <= 13, "#{queries} queries"
  end

  defp submit(c, items), do: ElementSets.submit(c.org, c.mission, items, [{:now, now()} | @opts])

  defp ids(rows), do: Enum.map(rows, & &1.element_set_id)

  defp now, do: ~U[2026-11-27 00:00:00.000000Z]

  defp insert_spacecraft!(organization_id, mission_id, count) do
    at = DateTime.utc_now()
    suffix = System.unique_integer([:positive])

    rows =
      for i <- 1..count do
        %{
          spacecraft_id: "craft-#{suffix}-#{i}",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "Craft #{i}",
          metadata: %{},
          lifecycle_state: "active",
          inserted_at: at
        }
      end

    {^count, _} = Repo.insert_all(SpacecraftRow, rows)
    Enum.map(rows, & &1.spacecraft_id)
  end

  defp count_queries(fun) do
    owner = self()
    handler = "element-sets-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, _meta, _config -> if self() == owner, do: send(owner, :query) end,
      nil
    )

    try do
      result = fun.()
      {drain(0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end

  # A synthetic LEO set at 2026-11-(20 + day): ~550 km, 53°, with `raan` spread per craft.
  defp tle(day, raan) do
    epoch = "26" <> String.pad_leading(Integer.to_string(323 + day), 3, "0") <> ".50000000"

    line1 =
      "1 99999U 26001A   #{epoch}  .00001000  00000-0  50000-4 0  999"

    raan = :erlang.float_to_binary(raan / 1, decimals: 4) |> String.pad_leading(8)
    line2 = "2 99999  53.0000 #{raan} 0001000  90.0000 270.0000 15.0500000000001"

    line1 <>
      Integer.to_string(checksum(line1)) <> "\n" <> line2 <> Integer.to_string(checksum(line2))
  end

  defp checksum(line) do
    line
    |> String.to_charlist()
    |> Enum.reduce(0, fn
      char, sum when char in ?0..?9 -> sum + char - ?0
      ?-, sum -> sum + 1
      _char, sum -> sum
    end)
    |> rem(10)
  end
end
