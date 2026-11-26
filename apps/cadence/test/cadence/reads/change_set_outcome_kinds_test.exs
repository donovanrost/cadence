defmodule Cadence.Reads.ChangeSetOutcomeKindsTest do
  @moduledoc """
  #522 follow-up (domain): every registered configuration kind is classified for the preview's
  readiness read, either as read (`readiness_kinds/0`) or as not read (`not_read_kinds/0`).
  A new kind fails here until someone decides which, so readiness-after can't silently miss it.
  """
  use ExUnit.Case, async: true

  alias Cadence.Configuration.Kinds
  alias Cadence.Reads.ChangeSetOutcome

  test "every registered kind is in exactly one list" do
    registered = Kinds.all() |> Enum.map(& &1.kind()) |> MapSet.new()
    read = MapSet.new(ChangeSetOutcome.readiness_kinds())
    not_read = MapSet.new(ChangeSetOutcome.not_read_kinds())

    assert MapSet.disjoint?(read, not_read)

    unclassified = MapSet.difference(registered, MapSet.union(read, not_read))

    assert MapSet.size(unclassified) == 0,
           "classify #{inspect(MapSet.to_list(unclassified))} in Reads.ChangeSetOutcome"

    # And neither list names a kind that isn't registered any more.
    assert MapSet.subset?(MapSet.union(read, not_read), registered)
  end
end
