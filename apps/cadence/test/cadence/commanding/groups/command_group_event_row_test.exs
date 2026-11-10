defmodule Cadence.Commanding.Groups.CommandGroupEventRowTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.Groups.CommandGroupEventRow
  alias Cadence.Persistence.JsonDocument

  defp row(kind),
    do: %CommandGroupEventRow{
      event_id: "e1",
      kind: kind,
      actor_document: nil,
      payload_document: JsonDocument.wrap_value(%{})
    }

  # qa #39: decoding never relies on an atom already being loaded.
  test "every known kind decodes to its atom; an unknown kind stays a string" do
    for kind <- ~w(submitted member_failed completed hold_acknowledged) do
      assert CommandGroupEventRow.to_domain(row(kind)).kind == String.to_atom(kind)
    end

    assert CommandGroupEventRow.to_domain(row("from_the_future")).kind == "from_the_future"
  end
end
