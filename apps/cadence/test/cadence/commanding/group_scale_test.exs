defmodule Cadence.Commanding.GroupScaleTest do
  @moduledoc """
  #708 / TEAM.md rule 3: a command group is set-based. Preflight and submit cost the same number
  of queries for 500 targets as for a handful, so a 500-spacecraft constellation is one bulk
  read and one bulk write, never a round trip per target.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandPreflight

  @small 5
  @large 500

  setup do
    setup!(@large)
  end

  defp draft_for(c, count) do
    draft(
      Enum.take(c.spacecraft, count),
      [command(c, "SET_SIGNED", %{"counter" => 1}), command(c, "SET_COUNTER", %{"amount" => 2})],
      %{log_entry: "Scale check"}
    )
  end

  test "preflight and submit cost the same queries at 500 targets as at 5", c do
    {small_preflight, _ms, small_queries} =
      measure(fn -> CommandPreflight.run(c.org, c.mission, actor(c), draft_for(c, @small)) end)

    {large_preflight, large_ms, large_queries} =
      measure(fn -> CommandPreflight.run(c.org, c.mission, actor(c), draft_for(c, @large)) end)

    assert {:ok, %{members: _}} = small_preflight
    assert {:ok, %{members: members}} = large_preflight
    assert members == @large * 2

    # Allow a few queries of slack; a per-target query would add hundreds.
    assert large_queries <= small_queries + 5,
           "preflight ran #{large_queries} queries for #{@large} targets, #{small_queries} for #{@small}"

    IO.puts("preflight #{@large}x2: #{large_queries} queries, #{large_ms} ms")

    small_draft = draft_for(c, @small)

    {{:ok, _small_group}, _ms, small_submit} =
      measure(fn ->
        GroupSubmission.submit(c.scope, c.mission, small_draft,
          preflight_digest: digest(c, small_draft)
        )
      end)

    large_draft = draft_for(c, @large)
    large_digest = digest(c, large_draft)

    {{:ok, group}, submit_ms, large_submit} =
      measure(fn ->
        GroupSubmission.submit(c.scope, c.mission, large_draft, preflight_digest: large_digest)
      end)

    assert group.member_count == @large * 2

    assert large_submit <= small_submit + 5,
           "submit ran #{large_submit} queries for #{@large} targets, #{small_submit} for #{@small}"

    IO.puts("submit #{@large}x2: #{large_submit} queries, #{submit_ms} ms")
  end

  # {result, milliseconds, queries run by this process}.
  defp measure(fun) do
    test_pid = self()
    handler = "group-scale-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    started = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      {result, System.monotonic_time(:millisecond) - started, :counters.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end
end
