defmodule Cadence.Reads.Spacecraft.PinnedProfile do
  @moduledoc "Resolves the exact profile version selected by a spacecraft."
  defdelegate load(mission, spacecraft), to: Cadence.SpacecraftStore, as: :fetch_pinned_profile
end
