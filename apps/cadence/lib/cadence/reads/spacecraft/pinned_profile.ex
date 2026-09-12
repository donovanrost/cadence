defmodule Cadence.Reads.Spacecraft.PinnedProfile do
  @moduledoc "Resolves the exact profile version selected by a spacecraft."
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.SpacecraftTypeStore
  def load(_mission, %SpacecraftAsset{spacecraft_type_id: nil}), do: {:ok, nil}

  def load(mission, %SpacecraftAsset{
        spacecraft_type_id: type_id,
        spacecraft_type_version: version
      })
      when is_binary(type_id) and is_integer(version) do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           mission.organization_id,
           mission.mission_id,
           type_id,
           version
         ) do
      {:ok, profile} -> {:ok, profile}
      {:error, _reason} -> {:ok, nil}
    end
  end

  def load(_mission, _spacecraft), do: {:ok, nil}
end
