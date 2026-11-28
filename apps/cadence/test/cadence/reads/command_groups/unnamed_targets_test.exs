defmodule Cadence.Reads.CommandGroups.UnnamedTargetsTest do
  @moduledoc """
  #1064: GO's unnamed-target check covers the whole group, not the first targets page. A target is
  unnamed when it has no name to show (nil or empty: the console's `!target.name`). `targets_page.unnamed`
  counts them over every target; `unnamed=true` lists them.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures
  import Ecto.Query

  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandGroups
  alias Cadence.Reads.CommandGroups.Page
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpointRow

  @crafts 120

  setup do
    setup!(@crafts)
  end

  defp unname!(craft, name) do
    id = Cadence.SourceEndpoints.managed_source_endpoint_id(craft)

    Repo.update_all(from(e in SourceEndpointRow, where: e.source_endpoint_id == ^id),
      set: [display_name: name]
    )
  end

  defp submit!(c, craft) do
    draft = draft(craft, [command(c, "SET_SIGNED", %{"counter" => 1})], %{log_entry: "Routine"})

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    group
  end

  # The group read, whole: what `Page` pages and counts.
  defp read(c, group) do
    {:ok, view} = CommandGroups.get(c.org, c.mission, group.command_group_id, nil)
    view
  end

  test "the only unnamed target is past the first page, and the whole-group count has it", c do
    last = List.last(c.spacecraft)
    unname!(last, "")
    full = read(c, submit!(c, c.spacecraft))
    first = Page.first(full)

    # The first page (100) holds no unnamed target; the count and the filter still find it.
    assert length(first.targets) == 100
    refute Enum.any?(first.targets, &(&1.name in [nil, ""]))
    assert %{total: 120, unnamed: 1} = first.targets_page

    assert {:ok, %{total: 1, targets: [%{spacecraft_id: ^last, index: 119}], next_cursor: nil}} =
             Page.targets(full, %{"unnamed" => "true"})
  end

  test "nil and empty are unnamed, a named target is not, whichever read carries the count", c do
    [first, second | rest] = c.spacecraft
    unname!(first, nil)
    unname!(second, "")
    full = read(c, submit!(c, [first, second | Enum.take(rest, 8)]))

    assert Page.first(full).targets_page.unnamed == 2

    assert {:ok, %{total: 2, targets: targets}} = Page.targets(full, %{"unnamed" => "true"})
    assert Enum.map(targets, & &1.spacecraft_id) == [first, second]
    assert {:ok, %{total: 10}} = Page.targets(full, %{"unnamed" => "false"})
    assert {:ok, %{total: 10}} = Page.targets(full, %{})

    # It combines with the other filters.
    assert {:ok, %{total: 1}} = Page.targets(full, %{"unnamed" => "true", "q" => first})

    assert {:error, {:invalid_params, %{"unnamed" => _}}} =
             Page.targets(full, %{"unnamed" => "yes"})
  end

  test "the whole-group count takes the same queries for 5 targets as for 50", c do
    unname!(Enum.at(c.spacecraft, 3), "")

    few = submit!(c, Enum.take(c.spacecraft, 5))
    many = submit!(c, Enum.take(c.spacecraft, 50))

    {few_queries, few_view} = count_queries(fn -> c |> read(few) |> Page.first() end)
    {many_queries, many_view} = count_queries(fn -> c |> read(many) |> Page.first() end)

    assert few_view.targets_page.unnamed == 1 and many_view.targets_page.unnamed == 1
    assert many_queries <= few_queries + 2, "#{few_queries} for 5 targets, #{many_queries} for 50"
  end

  defp count_queries(fun) do
    ref = make_ref()
    me = self()
    handler = "unnamed-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, _meta, _cfg -> if self() == me, do: send(me, {:query, ref}) end,
      nil
    )

    try do
      result = fun.()
      {drain(ref, 0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, n) do
    receive do
      {:query, ^ref} -> drain(ref, n + 1)
    after
      0 -> n
    end
  end
end
