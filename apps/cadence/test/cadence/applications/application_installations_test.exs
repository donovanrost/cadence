defmodule Cadence.Applications.ApplicationInstallationsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationInstallations,
    ConfigurationReference,
    HostContext
  }

  alias Cadence.Auth.Scope
  alias Cadence.Spacecraft

  @organization_id "org-application-installations"
  @mission_id "mission-application-installations"
  @spacecraft_id "spacecraft-application-installations"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "Installation Test Spacecraft"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "installation-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.spacecraft(@mission_id, @spacecraft_id)

    %{scope: scope, host_context: host_context}
  end

  test "installs once per application and scope and records an idempotent lifecycle", context do
    assert {:ok, installed} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert installed.application_key == "telemetry_decom"
    assert installed.application_version == 1
    assert installed.scope_kind == :spacecraft
    assert installed.scope_id == @spacecraft_id
    assert installed.lifecycle_state == :installed
    assert installed.configuration_ref == nil

    assert {:ok, same_installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert same_installation.application_installation_id ==
             installed.application_installation_id

    assert {:ok, [listed]} =
             ApplicationInstallations.list(context.scope, context.host_context)

    assert listed.application_installation_id == installed.application_installation_id

    assert {:ok, [event]} =
             ApplicationInstallations.list_events(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert event.event_type == :installed
    assert event.actor_id == "installation-operator"
  end

  test "retains configuration across disable, uninstall, and reinstall transitions", context do
    assert {:ok, installed} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    configuration_ref = %ConfigurationReference{
      kind: "spacecraft_application_binding",
      id: "binding-1",
      version: 3
    }

    assert {:ok, configured} =
             ApplicationInstallations.put_configuration_reference(
               context.scope,
               context.host_context,
               "telemetry_decom",
               configuration_ref
             )

    assert configured.configuration_ref == configuration_ref

    assert {:ok, disabled} =
             ApplicationInstallations.disable(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert disabled.lifecycle_state == :disabled

    assert {:error, :application_installation_disabled} =
             ApplicationInstallations.fetch_installed(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert {:ok, enabled} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert enabled.application_installation_id == installed.application_installation_id
    assert enabled.lifecycle_state == :installed
    assert enabled.configuration_ref == configuration_ref

    assert {:ok, uninstalled} =
             ApplicationInstallations.uninstall(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert uninstalled.application_installation_id == installed.application_installation_id
    assert uninstalled.lifecycle_state == :uninstalled
    assert uninstalled.configuration_ref == configuration_ref

    assert {:error, :application_installation_uninstalled} =
             ApplicationInstallations.fetch_installed(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert {:error, :application_installation_uninstalled} =
             ApplicationInstallations.put_configuration_reference(
               context.scope,
               context.host_context,
               "telemetry_decom",
               %ConfigurationReference{configuration_ref | version: 4}
             )

    assert {:ok, same_uninstalled} =
             ApplicationInstallations.uninstall(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert same_uninstalled == uninstalled

    assert {:ok, reinstalled} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert reinstalled.application_installation_id == installed.application_installation_id
    assert reinstalled.lifecycle_state == :installed
    assert reinstalled.configuration_ref == configuration_ref

    assert {:ok, events} =
             ApplicationInstallations.list_events(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert Enum.map(events, & &1.event_type) == [
             :installed,
             :configuration_updated,
             :disabled,
             :enabled,
             :uninstalled,
             :reinstalled
           ]
  end

  test "keeps mission installations independent from spacecraft installations", context do
    mission_host = HostContext.mission(@mission_id)

    assert {:ok, mission_installation} =
             ApplicationInstallations.install(
               context.scope,
               mission_host,
               "derived_telemetry"
             )

    assert mission_installation.scope_kind == :mission
    assert mission_installation.scope_id == @mission_id
    assert mission_installation.application_version == 1

    assert {:ok, spacecraft_installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert spacecraft_installation.scope_kind == :spacecraft
    assert spacecraft_installation.scope_id == @spacecraft_id

    assert {:ok, [listed_mission_installation]} =
             ApplicationInstallations.list(context.scope, mission_host)

    assert listed_mission_installation.application_installation_id ==
             mission_installation.application_installation_id

    assert {:ok, [listed_spacecraft_installation]} =
             ApplicationInstallations.list(context.scope, context.host_context)

    assert listed_spacecraft_installation.application_installation_id ==
             spacecraft_installation.application_installation_id
  end

  test "requires mission authority for installation mutations", context do
    unauthorized_scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "unauthorized-operator"}
    }

    assert {:error, :forbidden} =
             ApplicationInstallations.install(
               unauthorized_scope,
               HostContext.mission(@mission_id),
               "derived_telemetry"
             )

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               HostContext.mission(@mission_id),
               "derived_telemetry"
             )

    assert {:error, :forbidden} =
             ApplicationInstallations.disable(
               unauthorized_scope,
               HostContext.mission(@mission_id),
               "derived_telemetry"
             )

    assert {:error, :forbidden} =
             ApplicationInstallations.uninstall(
               unauthorized_scope,
               HostContext.mission(@mission_id),
               "derived_telemetry"
             )

    assert {:error, :forbidden} =
             ApplicationInstallations.fetch(
               unauthorized_scope,
               HostContext.mission(@mission_id),
               "derived_telemetry"
             )

    assert {:error, :forbidden} =
             ApplicationInstallations.list(
               unauthorized_scope,
               HostContext.mission(@mission_id)
             )
  end

  test "rejects applications on unsupported hosts and requires an installed record", context do
    assert {:error, :unsupported_application_host_context} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "derived_telemetry"
             )

    assert {:error, :application_not_installed} =
             ApplicationInstallations.fetch_installed(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )
  end

  test "action dispatch requires an exact installed configuration version", context do
    request = %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      action_id: "disable"
    }

    assert {:error, :application_not_installed} =
             ActionDispatcher.dispatch(context.scope, context.host_context, request)

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.host_context,
               "telemetry_decom"
             )

    assert {:ok, _installation} =
             ApplicationInstallations.put_configuration_reference(
               context.scope,
               context.host_context,
               "telemetry_decom",
               %ConfigurationReference{
                 kind: "spacecraft_application_binding",
                 id: "binding-1",
                 version: 3
               }
             )

    stale_request = %ActionRequest{request | expected_configuration_version: 2}

    assert {:error, {:application_configuration_version_conflict, 2, 3}} =
             ActionDispatcher.dispatch(context.scope, context.host_context, stale_request)
  end
end
