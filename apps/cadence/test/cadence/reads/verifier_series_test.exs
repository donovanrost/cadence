defmodule Cadence.Reads.VerifierSeriesTest do
  @moduledoc "M26: what Uplink U2 plots for a command group."
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Catalog.Command.Compiler.VerifierPlan
  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.VerifierSeries
  alias Cadence.Telemetry.Sample

  setup do
    c = setup!(2)
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    Map.merge(c, %{
      group: group,
      members: GroupStore.members(c.org, c.mission, group.command_group_id)
    })
  end

  @semantic "semantic:parameter:0123abcd"
  @therm %{
    point_id: "THERM.setpoint",
    parameter_id: @semantic,
    field_name: "setpoint",
    unit: "degC",
    data_type: :float
  }

  defp sample(spacecraft_id, value, seconds),
    do: %Sample{
      spacecraft_id: spacecraft_id,
      point_id: "THERM.setpoint",
      engineering_value: value,
      generation_time: DateTime.add(~U[2026-11-11 12:00:00Z], seconds)
    }

  defp opts(c, extra \\ [], subject \\ "telemetry:THERM.setpoint") do
    plan = %VerifierPlan{
      phase: :completion,
      success_criteria:
        MatchCriteria.new(%{
          subject_ref: subject,
          comparison: :equal,
          value: 8.0
        })
    }

    Keyword.merge(
      [
        plans_fun: fn _member -> [plan] end,
        releases_fun: fn ->
          Enum.map(
            c.members,
            &%{command_request_id: &1.command_request_id, released_at: ~U[2026-11-11 12:00:00Z]}
          )
        end,
        catalog_fun: fn -> [@therm] end,
        # Each read also returns another spacecraft's sample, which must never be plotted (#38).
        history_fun: fn "THERM.setpoint", spacecraft_id ->
          [
            sample(spacecraft_id, 5.0, 10),
            sample(spacecraft_id, 8.0, 40),
            sample("someone-else", 99, 20)
          ]
        end
      ],
      extra
    )
  end

  test "plots the telemetry verifier's point per target, own spacecraft only", c do
    {:ok, series} = VerifierSeries.load(c.org, c.mission, c.group.command_group_id, opts(c))

    assert %{
             point: %{id: "THERM.setpoint", name: "setpoint", unit: "degC"},
             reason: nil,
             commanded: %{value_json: "8.0", comparison: :equal},
             verifier: %{position: 0, command_name: "SET_SIGNED"},
             target_count: 2,
             truncated: false,
             telemetry: :ok,
             window: %{from: ~U[2026-11-11 12:00:00Z]}
           } = series

    assert [%{samples: first}, %{samples: second}] = series.targets
    assert Enum.map(first, & &1.value_json) == ["5.0", "8.0"]
    assert length(second) == 2
  end

  test "targets picks a subset and says the rest are left out", c do
    [sc1 | _] = c.spacecraft

    {:ok, series} =
      VerifierSeries.load(c.org, c.mission, c.group.command_group_id, opts(c, target_ids: [sc1]))

    assert [%{spacecraft_id: ^sc1}] = series.targets
    assert series.truncated
  end

  test "a slow history store degrades instead of holding the read", c do
    slow = fn _point_id, _spacecraft_id -> Process.sleep(10_000) end

    {:ok, series} =
      VerifierSeries.load(c.org, c.mission, c.group.command_group_id, opts(c, history_fun: slow))

    assert series.telemetry == :degraded
    assert Enum.all?(series.targets, &(&1.samples == []))
  end

  test "a mission-model verifier (semantic parameter id) plots its catalog point", c do
    {:ok, series} =
      VerifierSeries.load(c.org, c.mission, c.group.command_group_id, opts(c, [], @semantic))

    # The history read is keyed by the catalog point (the fun only matches "THERM.setpoint").
    assert %{id: "THERM.setpoint", name: "setpoint", unit: "degC"} = series.point
    assert [%{samples: [_, _]}, %{samples: [_, _]}] = series.targets
  end

  test "a subject no active point has keeps its id, with unit and type null", c do
    {:ok, series} =
      VerifierSeries.load(
        c.org,
        c.mission,
        c.group.command_group_id,
        opts(c, [catalog_fun: fn -> [] end, history_fun: fn _point, _sc -> [] end], @semantic)
      )

    assert series.point == %{id: @semantic, name: @semantic, unit: nil, type: nil}
  end
end
