defmodule Cadence.Reads.ApplicationSurfaces.TrustedSurfaceContractTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @organization_id "org-trusted-surface-contract"
  @mission_id "mission-trusted-surface-contract"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "trusted-surface-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope, host_context: HostContext.mission(@mission_id)}
  end

  test "deep trusted configuration forms stay inside the output boundary", context do
    assert {:ok, _payload} =
             OpsConsole.load(
               context.scope,
               context.host_context,
               request("data_source_registration")
             )
  end

  defp request(surface_id) do
    %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: "cadence.ops.#{surface_id}",
      query_version: 1,
      params: %{}
    }
  end
end
