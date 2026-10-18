defmodule Cadence.Reads.ApplicationSurfaces.SpacecraftTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry

  @organization_id "org-spacecraft-surface-provider"
  @mission_id "mission-spacecraft-surface-provider"
  @spacecraft_id "spacecraft-surface-provider"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Cadence.Spacecraft.new(%{
        organization_id: @organization_id,
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        display_name: "Provider Test Vehicle",
        scid: 7
      })

    assert {:ok, _spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      user: %{user_id: "spacecraft-surface-user"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{
      scope: scope,
      providers: ProviderRegistry.providers()
    }
  end

  test "dispatches Spacecraft queries through the default central provider registry", context do
    assert Enum.all?(
             [
               "cadence.spacecraft.applications",
               "cadence.spacecraft.edit",
               "cadence.spacecraft.list",
               "cadence.spacecraft.new",
               "cadence.spacecraft.profile.new",
               "cadence.spacecraft.profile.show",
               "cadence.spacecraft.profiles",
               "cadence.spacecraft.readiness",
               "cadence.spacecraft.routing",
               "cadence.spacecraft.show",
               "cadence.spacecraft.commanding"
             ],
             &Map.has_key?(context.providers, {"spacecraft", &1})
           )

    assert Map.has_key?(context.providers, {"telemetry_decom", "cadence.telemetry_decom.manage"})
    refute Map.has_key?(context.providers, {"spacecraft", "cadence.telemetry_decom.manage"})

    assert {:ok, %{"data" => %{"page" => %{"id" => "spacecraft-new-page"}}}} =
             dispatch(context, HostContext.mission(@mission_id), "new", "cadence.spacecraft.new")

    assert {:ok, %{"data" => %{"page" => %{"id" => "spacecraft-show-page"}}}} =
             dispatch(
               context,
               HostContext.spacecraft(@mission_id, @spacecraft_id),
               "show",
               "cadence.spacecraft.show"
             )
  end

  test "requires the profile detail parameter and rejects cross-scope contexts", context do
    assert {:error, :invalid_application_request} =
             dispatch(
               context,
               HostContext.mission(@mission_id),
               "profile_show",
               "cadence.spacecraft.profile.show"
             )

    assert {:error, :unsupported_application_host_context} =
             dispatch(
               context,
               HostContext.spacecraft(@mission_id, @spacecraft_id),
               "list",
               "cadence.spacecraft.list"
             )

    assert {:error, :unsupported_application_host_context} =
             dispatch(
               context,
               HostContext.mission(@mission_id),
               "show",
               "cadence.spacecraft.show"
             )

    %Scope{} = scope = context.scope
    mismatched_scope = %Scope{scope | mission_id: "another-mission"}

    assert {:error, :unsupported_application_surface_query} =
             ProviderRegistry.dispatch(
               mismatched_scope,
               HostContext.mission(@mission_id),
               request("list", "cadence.spacecraft.list"),
               context.providers
             )
  end

  defp dispatch(context, host_context, surface_id, query_id) do
    ProviderRegistry.dispatch(
      context.scope,
      host_context,
      request(surface_id, query_id),
      context.providers
    )
  end

  defp request(surface_id, query_id, params \\ %{}) do
    %SurfaceQueryRequest{
      application_key: "spacecraft",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: query_id,
      query_version: 1,
      params: params
    }
  end
end
