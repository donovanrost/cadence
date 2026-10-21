defmodule CadenceSimulator.Provider.SpacecraftFramesTest do
  use ExUnit.Case, async: true
  alias CadenceSimulator.Provider.SpacecraftFrames

  test "resolves distinct fleet identities while preserving unconfigured defaults" do
    profile = %{
      "spacecraft_frames" => %{
        "EARENDIL-001" => %{"scid" => 1},
        "EARENDIL-500" => %{"scid" => 500, "vcid" => 7}
      }
    }

    assert :ok = SpacecraftFrames.validate(profile)
    assert %{"scid" => 1} = SpacecraftFrames.for_spacecraft(profile, "EARENDIL-001")

    assert %{"scid" => 500, "vcid" => 7} =
             SpacecraftFrames.for_spacecraft(profile, "EARENDIL-500")

    assert %{} == SpacecraftFrames.for_spacecraft(profile, "unconfigured")
    assert :ok = SpacecraftFrames.validate(%{})
  end

  test "rejects invalid TM identities before a scenario can start streams" do
    for frame <- [
          %{"scid" => -1},
          %{"scid" => 1024},
          %{"scid" => "1"},
          %{"scid" => 1, "vcid" => 8},
          %{"scid" => 1, "host" => "elsewhere"}
        ] do
      assert {:error, {:invalid, "telemetry_profile.spacecraft_frames"}} =
               SpacecraftFrames.validate(%{"spacecraft_frames" => %{"SC-001" => frame}})
    end

    assert {:error, _} = SpacecraftFrames.validate(%{"spacecraft_frames" => []})
    assert {:error, _} = SpacecraftFrames.validate(nil)
  end
end
