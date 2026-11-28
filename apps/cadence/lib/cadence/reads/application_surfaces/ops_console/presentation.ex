defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole.Presentation do
  @moduledoc "Compatibility identities for domain-owned data-source pages."

  @spec data_sources(map(), map(), map(), :reader | :registration | :settings) :: map()
  def data_sources(_scope, mission, params, mode) do
    %{
      "page" => %{
        "mission_id" => mission.mission_id,
        "mode" => Atom.to_string(mode),
        "data_source_id" => params["data_source_id"]
      }
    }
  end
end
