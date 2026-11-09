defmodule Cadence.Reads.CommandEndpoints do
  @moduledoc """
  For Compose's per-target endpoint picker (DECISIONS #41): how each
  spacecraft's uplink endpoint resolves from its routes, and the endpoints an
  operator could choose instead (an explicit choice is an audited override).
  """

  alias Cadence.Comms.UplinkResolution
  alias Cadence.SourceEndpoints

  @spec for_spacecraft(binary(), binary(), [binary()]) :: [map()]
  def for_spacecraft(organization_id, mission_id, spacecraft_ids) do
    endpoints =
      organization_id
      |> SourceEndpoints.list_source_endpoints(mission_id)
      |> Enum.group_by(& &1.spacecraft_id)

    organization_id
    |> UplinkResolution.annotate(
      mission_id,
      Enum.map(spacecraft_ids, &%{spacecraft_id: &1, source_endpoint_id: nil})
    )
    |> Enum.map(fn target ->
      managed = SourceEndpoints.managed_source_endpoint_id(target.spacecraft_id)

      %{
        spacecraft_id: target.spacecraft_id,
        resolved_source_endpoint_id: Map.get(target, :source_endpoint_id),
        failure: Map.get(target, :failure),
        routes: routes(target),
        endpoints:
          endpoints
          |> Map.get(target.spacecraft_id, [])
          |> Enum.map(
            &%{
              id: &1.source_endpoint_id,
              name: &1.display_name,
              scid: &1.scid,
              managed: &1.source_endpoint_id == managed
            }
          )
      }
    end)
  end

  defp routes(%{resolution: %{routes: routes}}), do: routes
  defp routes(target), do: Map.get(target, :failure_detail, [])
end
