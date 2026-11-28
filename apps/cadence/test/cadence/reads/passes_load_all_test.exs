defmodule Cadence.Reads.PassesLoadAllTest do
  @moduledoc """
  `Passes.load_all/6` (#1040): every pass matching the filters, paged by the keyset until the read
  is complete, or `{:error, :truncated}`, never a silently cut list.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Reads.Passes

  setup do
    c = setup!(3)
    now = DateTime.utc_now()

    specs =
      for {id, i} <- Enum.with_index(c.spacecraft, 1),
          j <- 1..3,
          do: {id, DateTime.add(now, i * 100 + j * 10 + 60)}

    commandable_passes!(c.org, c.mission, specs)
    Map.merge(c, %{from: now, to: DateTime.add(now, 3_600)})
  end

  defp load_all(c, filters, pages \\ 40),
    do: Passes.load_all(c.org, c.mission, c.from, c.to, filters, pages)

  test "pages until the read is complete, in order, with nothing repeated or lost", c do
    assert {:ok, whole} = load_all(c, %{states: ["confirmed"], limit: 1_000})
    assert length(whole) == 9

    for limit <- [1, 2, 4, 8, 9] do
      assert {:ok, paged} = load_all(c, %{states: ["confirmed"], limit: limit})
      assert Enum.map(paged, & &1.id) == Enum.map(whole, & &1.id), "limit #{limit}"
    end
  end

  test "reads only the given craft's passes", c do
    [first, second | _] = c.spacecraft

    assert {:ok, passes} =
             load_all(c, %{states: ["confirmed"], spacecraft_ids: [first, second], limit: 2})

    assert length(passes) == 6

    assert passes |> Enum.map(& &1.spacecraft_id) |> Enum.uniq() |> Enum.sort() ==
             Enum.sort([first, second])

    assert {:ok, []} = load_all(c, %{states: ["confirmed"], spacecraft_ids: ["nobody"]})
  end

  test "a read that still isn't the whole answer after the pages allowed is an error", c do
    assert {:error, :truncated} = load_all(c, %{states: ["confirmed"], limit: 2}, 2)
    assert {:ok, passes} = load_all(c, %{states: ["confirmed"], limit: 2}, 5)
    assert length(passes) == 9
  end
end
