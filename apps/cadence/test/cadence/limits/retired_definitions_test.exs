defmodule Cadence.Limits.RetiredDefinitionsTest do
  @moduledoc """
  #481: `Limits.list_limit_definitions/1` (what "limits configured" reads in the fleet, counts and
  the action queue) leaves out a definition whose latest version was retired. Retiring keeps the
  versions, so the latest-version list alone kept counting it.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Limits
  alias Cadence.Limits.{ActiveLimitDefinitionRow, LimitDefinitionLifecycleEventRow}

  @org "org-retired-limits"
  @mission "mission-retired-limits"

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  test "a retired definition isn't listed; the others are" do
    voltage = append!("HK.bus_voltage")
    _current = append!("HK.bus_current")

    retire!(voltage.point_id)

    assert listed() == ["HK.bus_current"]
  end

  test "with every definition retired, none is listed" do
    append!("HK.bus_voltage")
    retire!("HK.bus_voltage")

    assert Limits.list_limit_definitions(@mission) == []
  end

  test "a definition appended again after retirement is listed with its new version" do
    append!("HK.bus_voltage")
    retire!("HK.bus_voltage")
    again = append!("HK.bus_voltage", 30)

    assert [%{point_id: "HK.bus_voltage", version: version}] =
             Limits.list_limit_definitions(@mission)

    assert version == again.version and version > 1
  end

  test "a definition with no lifecycle record at all (from before #77) is still listed" do
    append!("HK.bus_voltage")
    Repo.delete_all(LimitDefinitionLifecycleEventRow)
    Repo.delete_all(ActiveLimitDefinitionRow)

    assert listed() == ["HK.bus_voltage"]
  end

  defp append!(point_id, threshold \\ 20) do
    review = Limits.limit_definition_review(@org, @mission, point_id, "FLIGHT")

    {:ok, definition} =
      Limits.append_limit_definition(
        @org,
        @mission,
        %{
          point_id: point_id,
          limit_set_name: "FLIGHT",
          thresholds: %{"yellow_high" => threshold}
        },
        review
      )

    definition
  end

  defp retire!(point_id) do
    definition =
      @org |> Limits.active_limit_definitions(@mission) |> Enum.find(&(&1.point_id == point_id))

    {:ok, _event} = Limits.retire_limit_definition(@org, @mission, definition)
  end

  defp listed, do: @mission |> Limits.list_limit_definitions() |> Enum.map(& &1.point_id)
end
