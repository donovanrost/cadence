defmodule Cadence.Reads.ApplicationSurfaces.OpsConsole.Presentation do
  @moduledoc "Compatibility identities for domain-owned data-source and workflow pages."

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

  @spec data_operations(map(), map(), map(), :reader | :manage) :: map()
  def data_operations(_scope, mission, params, mode) do
    %{
      "mission_id" => mission.mission_id,
      "mode" => Atom.to_string(mode),
      "query" => Map.take(params, ["group"])
    }
  end
end
