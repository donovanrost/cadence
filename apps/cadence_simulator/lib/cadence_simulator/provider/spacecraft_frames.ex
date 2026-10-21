defmodule CadenceSimulator.Provider.SpacecraftFrames do
  @moduledoc "Scenario-owned TM identities for spacecraft sharing a provider delivery endpoint."

  @spec validate(term()) :: :ok | {:error, {:invalid, binary()}}
  def validate(profile) when is_map(profile) do
    frames = Map.get(profile, "spacecraft_frames", %{})

    if is_map(frames) and map_size(frames) <= 10_000 and
         Enum.all?(frames, &valid_entry?/1) do
      :ok
    else
      {:error, {:invalid, "telemetry_profile.spacecraft_frames"}}
    end
  end

  def validate(_), do: {:error, {:invalid, "telemetry_profile"}}

  @spec for_spacecraft(map(), binary() | nil) :: map()
  def for_spacecraft(profile, spacecraft_ref) do
    profile |> Map.get("spacecraft_frames", %{}) |> Map.get(spacecraft_ref, %{})
  end

  defp valid_entry?({id, frame})
       when is_binary(id) and byte_size(id) in 1..255 and is_map(frame) do
    Enum.all?(Map.keys(frame), &(&1 in ["scid", "vcid"])) and
      is_integer(frame["scid"]) and frame["scid"] in 0..1023 and
      is_integer(Map.get(frame, "vcid", 0)) and Map.get(frame, "vcid", 0) in 0..7
  end

  defp valid_entry?(_), do: false
end
