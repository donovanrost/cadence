defmodule CadenceWeb.ApplicationInventoryTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.HostContext
  alias CadenceWeb.ApplicationInventory

  test "keeps inventory DOM IDs stable outside the retired renderer" do
    assert ApplicationInventory.dom_id(HostContext.mission("mission-1"), "telemetry_decom") ==
             "mission-application-telemetry_decom"

    assert ApplicationInventory.dom_id(
             HostContext.spacecraft("mission-1", "spacecraft-1"),
             "custom.thermal/alerting"
           ) == "spacecraft-application-custom-thermal-alerting"
  end
end
