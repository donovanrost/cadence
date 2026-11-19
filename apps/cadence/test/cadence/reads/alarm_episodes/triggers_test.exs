defmodule Cadence.Reads.AlarmEpisodes.TriggersTest do
  @moduledoc "U68 R5: a catalog-monitoring episode has no producing definition or sample id."
  use Cadence.DataCase, async: true

  alias Cadence.Reads.AlarmEpisodes.Triggers

  test "a catalog-monitoring episode triggers at its opening, with no sample or definition" do
    opened_at = ~U[2026-11-14 07:20:00.000000Z]

    episode = %{
      source: :catalog_monitoring,
      point: %{id: "HK.temp"},
      opened_at: opened_at,
      opened_by_ref: "transition-1",
      context: %{"policy_id" => "policy-1"},
      events: [
        %{kind: :raised, at: opened_at, source_ref: "transition-1"},
        %{kind: :note, at: opened_at, source_ref: nil}
      ]
    }

    assert [
             %{
               limit_definition_id: nil,
               limit_definition_version: nil,
               limit_set_name: nil,
               trigger: %{
                 sample_id: nil,
                 sample_type: nil,
                 point_id: "HK.temp",
                 at: ^opened_at,
                 receipt_time: nil
               },
               events: [%{sample: %{id: nil, at: ^opened_at, receipt_time: nil}}, %{sample: nil}]
             }
           ] = Triggers.put("org", "mission", [episode])
  end
end
