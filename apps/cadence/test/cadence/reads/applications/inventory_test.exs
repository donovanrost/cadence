defmodule Cadence.Reads.Applications.InventoryTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Applications.ApplicationInstallations.InstallationRow
  alias Cadence.Auth.Scope
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications.Inventory
  alias Cadence.Spacecraft

  @organization_id "org-application-inventory"
  @mission_id "mission-application-inventory"
  @spacecraft_id "spacecraft-application-inventory"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "Inventory Test Spacecraft"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "application-inventory-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{
      scope: scope,
      mission_host: HostContext.mission(@mission_id),
      spacecraft_host: HostContext.spacecraft(@mission_id, @spacecraft_id)
    }
  end

  test "catalog inventory composes available definitions with lifecycle state", context do
    definitions = ExtensionCatalog.available_applications_for_scope(:mission)

    assert {:ok, applications} =
             Inventory.catalog(context.scope, context.mission_host, definitions)

    assert Enum.map(applications, & &1.application_key) == ["derived_telemetry", "limits"]

    assert Enum.all?(applications, fn application ->
             not application.declared? and
               application.installable? and
               not application.manageable? and
               application.lifecycle_state == nil and
               application.status.state == :not_installed
           end)
  end

  test "declared inventory preserves package metadata and unknown extension keys", context do
    declarations = %{
      "custom:thermal-alerting" => %{
        "display_name" => "Thermal Alerting",
        "description" => "Mission-owned temperature monitoring."
      },
      "telemetry_decom" => %{}
    }

    assert {:ok, [custom, telemetry]} =
             Inventory.declared(
               context.scope,
               context.spacecraft_host,
               declarations,
               ExtensionCatalog.applications_for_scope(:spacecraft)
             )

    assert custom.application_key == "custom:thermal-alerting"
    assert custom.display_name == "Thermal Alerting"
    assert custom.definition == nil
    assert custom.declared?
    assert custom.status.state == :unavailable
    refute custom.installable?

    assert telemetry.application_key == "telemetry_decom"
    assert telemetry.application_version == 1
    assert telemetry.declared?
    assert telemetry.status.state == :not_installed
    assert telemetry.installable?
    refute telemetry.manageable?

    summary = Inventory.summary([custom, telemetry])
    assert summary.state == :blocked
    assert summary.label == "0 of 2 ready"
    assert summary.tone == :blocked
  end

  test "installed declared applications load status through the registered provider", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.spacecraft_host,
               "telemetry_decom"
             )

    assert {:ok, [telemetry]} =
             Inventory.declared(
               context.scope,
               context.spacecraft_host,
               %{"telemetry_decom" => %{}},
               ExtensionCatalog.applications_for_scope(:spacecraft)
             )

    assert telemetry.lifecycle_state == :installed
    assert telemetry.manageable?
    assert telemetry.uninstallable?
    assert telemetry.status.state == :not_configured
    assert telemetry.status.label == "Not configured"
    assert telemetry.status.tone == :blocked
  end

  test "retained installations remain visible when no profile declares them", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.spacecraft_host,
               "telemetry_decom"
             )

    assert {:ok, [telemetry]} =
             Inventory.declared(
               context.scope,
               context.spacecraft_host,
               %{},
               ExtensionCatalog.applications_for_scope(:spacecraft)
             )

    assert telemetry.application_key == "telemetry_decom"
    refute telemetry.declared?
    assert telemetry.lifecycle_state == :installed
    assert telemetry.manageable?
    assert telemetry.uninstallable?
    assert telemetry.status.state == :not_configured
  end

  test "installed versions that are absent from package discovery require an upgrade", context do
    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               context.spacecraft_host,
               "telemetry_decom"
             )

    assert {1, nil} =
             from(row in InstallationRow,
               where:
                 row.organization_id == ^@organization_id and
                   row.mission_id == ^@mission_id and
                   row.scope_id == ^@spacecraft_id and
                   row.application_key == "telemetry_decom"
             )
             |> Repo.update_all(set: [application_version: 99])

    assert {:ok, [telemetry]} =
             Inventory.declared(
               context.scope,
               context.spacecraft_host,
               %{"telemetry_decom" => %{}},
               ExtensionCatalog.applications_for_scope(:spacecraft)
             )

    assert telemetry.application_version == 99
    assert telemetry.lifecycle_state == :installed
    assert telemetry.status.state == :upgrade_required
    assert telemetry.status.label == "Upgrade required"
    assert telemetry.installable?
    refute telemetry.manageable?
    assert telemetry.uninstallable?
  end
end
