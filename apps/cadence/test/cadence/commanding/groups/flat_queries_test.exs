defmodule Cadence.Commanding.Groups.FlatQueriesTest do
  @moduledoc """
  #1041 / #1051: a command group's preflight, submit and GO take the same number of queries
  whatever the number of members, and whatever the size of the fleet around them (a request's
  query count must not grow with the fleet). A loop over targets or members, or a read of the
  whole fleet, that comes back fails here. Counted by the Repo's telemetry in this test's own
  process, as the repo's other query-count tests do; the allowance (`@slack`) is a small constant
  for chunking, never a per-member one.

  The same is run on a fleet activation (each craft has its own entry, the model's plans are
  loaded once per distinct model) and on one with enumerated arguments.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Reads.CommandPreflight

  @few 5
  @many 50
  @slack 2

  setup do
    c = setup!(@many)
    Map.merge(c, %{approver: operator!(c), few: Enum.take(c.spacecraft, @few)})
  end

  # (A group of ten or more targets needs a second GO by fleet reach, so it carries a log entry.)
  defp routine(c, craft, name \\ "SET_SIGNED", args \\ %{"counter" => 1}),
    do: draft(craft, [command(c, name, args)], %{log_entry: "Routine"})

  defp hazardous(c, craft),
    do: draft(craft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "Reset"})

  defp preflight(c, draft), do: CommandPreflight.run(c.org, c.mission, actor(c), draft)

  # What the console's create runs: the preflight (for the HOLDs), then the submit under its lock.
  defp create(c, draft) do
    {:ok, preflight} = preflight(c, draft)

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: preflight.digest)

    group
  end

  # What the console's GO runs: the review preflight, then the decision under its lock.
  defp go(c, group) do
    {:ok, _review} = CommandPreflight.review(c.org, c.mission, group)

    {:ok, _group} =
      GroupDecision.decide(c.approver, c.mission, group.command_group_id, %{
        kind: :go,
        expected_review: GroupDecision.review_token(group)
      })
  end

  # The fixed part (#1051): what one request reads whatever the group (the activation, the basis,
  # the lanes' open work, the response), with headroom of a few over today's count.
  @budget %{"preflight" => 24, "create" => 48, "create armed" => 50, "go" => 48}

  defp flat!(label, {few_label, run_few}, {many_label, run_many}) do
    {few, _} = count_queries(run_few)
    {many, _} = count_queries(run_many)
    IO.puts("QUERIES #{label}: #{few_label} #{few}, #{many_label} #{many}")

    assert many <= few + @slack,
           "#{label} took #{few} queries for #{few_label} and #{many} for #{many_label}"

    if budget = @budget[label],
      do: assert(few <= budget, "#{label} took #{few} queries, budget #{budget}")
  end

  defp by_members(label, c, make_draft) do
    flat!(
      label,
      {"#{@few} members", fn -> run(label, c, make_draft.(c.few)) end},
      {"#{@many} members", fn -> run(label, c, make_draft.(c.spacecraft)) end}
    )
  end

  defp run("preflight" <> _, c, draft), do: preflight(c, draft)
  defp run("create" <> _, c, draft), do: create(c, draft)

  describe "in the number of members" do
    test("preflight", c, do: by_members("preflight", c, &routine(c, &1)))

    test("create (preflight, then submit, waiting for its second GO)", c,
      do: by_members("create", c, &hazardous(c, &1))
    )

    test "create armed at submit (queues its members and wakes their lanes)", c do
      # Below the fleet-reach threshold of ten, a routine group is armed by its own submit.
      flat!(
        "create armed",
        {"3 members", fn -> create(c, no_log(c, Enum.take(c.spacecraft, 3))) end},
        {"9 members", fn -> create(c, no_log(c, Enum.take(c.spacecraft, 9))) end}
      )
    end

    test "GO (review, then decision)", c do
      few = create(c, hazardous(c, c.few))
      many = create(c, hazardous(c, c.spacecraft))

      flat!(
        "go",
        {"#{@few} members", fn -> go(c, few) end},
        {"#{@many} members", fn -> go(c, many) end}
      )
    end

    test "on a fleet activation, each craft with its own entry", c do
      pin_fleet!(c)
      by_members("preflight (fleet)", c, &routine(c, &1))
      by_members("create (fleet)", c, &hazardous(c, &1))
    end

    test "with an enumerated argument", c do
      by_members(
        "preflight (enum)",
        c,
        &routine(c, &1, "SET_ENUM", %{"counter" => 18_446_744_073_709_551_615})
      )
    end
  end

  describe "in the number of commands" do
    # A group stacks up to 16 commands; what it reads for each (the basis, its units) is shared.
    test "preflight and create, one command and three", c do
      one = fn craft ->
        draft(craft, [command(c, "SET_SIGNED", %{"counter" => 1})], %{log_entry: "R"})
      end

      three = fn craft ->
        draft(
          craft,
          [
            command(c, "SET_SIGNED", %{"counter" => 1}),
            command(c, "SET_ENUM", %{"counter" => 18_446_744_073_709_551_615}),
            command(c, "SET_COUNTER", %{"amount" => 2})
          ],
          %{log_entry: "R"}
        )
      end

      flat!(
        "preflight by commands",
        {"1 command", fn -> preflight(c, one.(c.few)) end},
        {"3 commands", fn -> preflight(c, three.(c.few)) end}
      )

      flat!(
        "create by commands",
        {"1 command", fn -> create(c, one.(c.few)) end},
        {"3 commands", fn -> create(c, three.(c.few)) end}
      )
    end
  end

  describe "in the size of the fleet" do
    # The same five-member group, in a mission of 5 craft and in one of 50.
    setup c do
      small = setup!(@few, "small")
      Map.put(c, :small, small)
    end

    test "preflight, create and GO", c do
      small = Map.put(c.small, :approver, operator!(c.small))

      for {label, make} <- [
            {"preflight", &preflight/2},
            {"create", &create/2}
          ] do
        flat!(
          label,
          {"a fleet of #{@few}", fn -> make.(small, routine(small, small.spacecraft)) end},
          {"a fleet of #{@many}", fn -> make.(c, routine(c, c.few)) end}
        )
      end

      group_small = create(small, hazardous(small, small.spacecraft))
      group_big = create(c, hazardous(c, c.few))

      flat!(
        "go",
        {"a fleet of #{@few}", fn -> go(small, group_small) end},
        {"a fleet of #{@many}", fn -> go(c, group_big) end}
      )
    end
  end

  defp no_log(c, craft), do: draft(craft, [command(c, "SET_SIGNED", %{"counter" => 1})])

  defp count_queries(fun) do
    ref = make_ref()
    me = self()
    handler = "flat-queries-#{inspect(ref)}"

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
