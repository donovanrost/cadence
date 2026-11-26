defmodule CadenceWeb.API.CommsJSON do
  @moduledoc "Spacecraft response serialization boundary."

  alias Cadence.Spacecraft

  def spacecraft(%Spacecraft{} = spacecraft) do
    %{
      spacecraft_id: spacecraft.spacecraft_id,
      organization_id: spacecraft.organization_id,
      mission_id: spacecraft.mission_id,
      display_name: spacecraft.display_name,
      scid: spacecraft.scid,
      metadata: spacecraft.metadata
    }
  end
end
