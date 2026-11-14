defmodule Cadence.Administration.PlatformBindingAuditTest do
  @moduledoc "ux U53's Admin › Audit line for a platform-wide binding switch (DECISIONS #90)."
  use Cadence.DataCase, async: true

  alias Cadence.Administration.{PlatformAudit, PlatformEvents}

  test "the line, singular and plural, and a count that wasn't recorded is left out" do
    from = %{"id" => "managed", "display_name" => "Cadence managed store"}
    to = %{"id" => "archive", "display_name" => "Northlight archive"}

    record("b-1", %{
      "from" => from,
      "to" => to,
      "reason" => "Move.",
      "affected_missions" => 12,
      "live_passes_total" => 1
    })

    record("b-2", %{"from" => from, "to" => to, "reason" => "Move.", "affected_missions" => 1})
    record("b-3", %{"from" => from, "to" => to, "reason" => "Move."})

    lines =
      PlatformEvents.list(limit: 10)
      |> PlatformAudit.events()
      |> Map.new(&{&1.target.id, &1.action})

    assert lines["b-1"] ==
             "Switched platform binding b-1 from Cadence managed store to Northlight archive · 12 missions, 1 live pass: “Move.”"

    assert lines["b-2"] ==
             "Switched platform binding b-2 from Cadence managed store to Northlight archive · 1 mission: “Move.”"

    assert lines["b-3"] ==
             "Switched platform binding b-3 from Cadence managed store to Northlight archive: “Move.”"
  end

  defp record(binding_id, details) do
    :ok =
      PlatformEvents.record("user-audit", "platform_binding_switched", %{
        target: {"data_source_binding", binding_id, binding_id},
        details: details
      })
  end
end
