defmodule Cadence.Applications.MissionBindingComposer do
  @moduledoc "Names the one mission runtime binding set that application contributions apply to."

  @spec binding_set_id(binary()) :: binary()
  def binding_set_id(mission_id) when is_binary(mission_id),
    do: "mission_applications:" <> mission_id
end
