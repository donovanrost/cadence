defmodule Cadence.Reads.MissionAppsTest do
  use ExUnit.Case, async: true

  alias Cadence.Reads.MissionApps

  describe "update_available?/3" do
    test "an installed or disabled app is behind when the shipped version is greater" do
      for state <- [:installed, :disabled] do
        assert MissionApps.update_available?(state, 1, 2)
      end
    end

    test "the same or an older shipped version is not an update" do
      refute MissionApps.update_available?(:installed, 2, 2)
      refute MissionApps.update_available?(:installed, 3, 2)
    end

    test "an app that is not installed, or without an installed version, has none" do
      refute MissionApps.update_available?(:not_installed, nil, 2)
      refute MissionApps.update_available?(:not_installed, 1, 2)
      refute MissionApps.update_available?(:installed, nil, 2)
    end
  end
end
