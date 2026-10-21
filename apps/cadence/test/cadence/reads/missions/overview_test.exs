defmodule Cadence.Reads.Missions.OverviewTest do
  use Cadence.DataCase, async: false

  alias Cadence.Reads.Missions.Overview

  test "provider mapping and runtime endpoints share the spacecraft's routing readiness" do
    context = Cadence.ContactScheduleFixtures.setup_schedule()

    assert {:ok, spacecraft} =
             Cadence.SpacecraftStore.update_spacecraft(
               context.organization_id,
               %{context.spacecraft | scid: 42}
             )

    endpoints =
      Cadence.SourceEndpoints.list_source_endpoints(context.organization_id, context.mission_id)

    assert length(endpoints) == 2
    assert {:ok, data} = Overview.load(context.organization_id, context.mission_id)
    assert [row] = data["spacecraft_readiness"]
    assert row["spacecraft_id"] == spacecraft.spacecraft_id
    assert row["status"] == "ready"
    assert row["path_label"] == "1 downlink route"
    assert row["issue"] == "Spacecraft identity and downlink routes are configured."
    cards = Map.new(data["overview"]["readiness_cards"], &{&1["title"], &1["value"]})
    assert cards["Ready Spacecraft"] == 1
    assert cards["Need Link"] == 0
  end
end
