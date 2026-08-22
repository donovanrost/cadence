defmodule Cadence.Runtime.Telemetry.ConfigBundleTest do
  use ExUnit.Case, async: false

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.Telemetry.ConfigBundle

  test "from_config caches target ids by scid with last-wins duplicates" do
    config = %MissionConfig{
      mission_id: "mission-1",
      organization_id: "org-1",
      config_generation: 7,
      targets: [
        %{id: "target-a", scid: 42},
        %{id: "target-b", scid: "not-an-int"},
        %{id: "target-c", scid: 42},
        %{id: "target-d", scid: 99}
      ]
    }

    bundle = ConfigBundle.from_config(config)

    assert bundle.target_ids_by_scid == %{42 => "target-c", 99 => "target-d"}
  end
end
