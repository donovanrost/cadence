defmodule Cadence.Contacts.LinkSetupTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Contacts.LinkAssignmentStore
  alias Cadence.Contacts.LinkSetup
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Contacts.TransportProfile
  alias Cadence.Spacecraft

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-link-setup-#{suffix}"
    mission_id = "mission-link-setup-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "creates a shared link and applies its template idempotently", context do
    attrs = %{
      "display_name" => "Primary Ground Link",
      "direction" => "downlink",
      "selection_role" => "selected",
      "tcp_mode" => "connect",
      "host" => "127.0.0.1",
      "port" => "4100",
      "framing_mode" => "fixed_size",
      "frame_size" => "256",
      "tls_enabled" => "false",
      "heartbeat_enabled" => "true",
      "heartbeat_interval_ms" => "1000"
    }

    assert {:ok,
            %{
              provider: %ProviderProfile{} = provider,
              transport: %TransportProfile{} = transport,
              path_templates: [%PathTemplate{} = template]
            }} =
             LinkSetup.create_shared_link(
               context.organization_id,
               context.mission_id,
               attrs
             )

    assert provider.configuration["fixed_message_bytes"] == 256
    assert transport.configuration == %{"heartbeat_interval_ms" => 1000}

    assert template.provider_profile_refs == [
             %{"provider_profile_id" => provider.provider_profile_id, "version" => 1}
           ]

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-1",
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        display_name: "Aurora",
        scid: 42
      })

    assert {:ok, spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(context.organization_id, spacecraft)

    application_attrs = %{
      "display_name_pattern" => "{spacecraft_name} {direction}",
      "provider_path_ref_pattern" => "{spacecraft_id}-{direction}"
    }

    assert {:ok, %{applied_count: 1, skipped_count: 0, failed_count: 0}} =
             LinkSetup.apply_link_template(
               context.organization_id,
               context.mission_id,
               template,
               [spacecraft],
               application_attrs
             )

    assert [%LinkAssignment{} = assignment] =
             LinkAssignmentStore.list(context.organization_id, context.mission_id)

    assert assignment.spacecraft_id == spacecraft.spacecraft_id
    assert assignment.path_template_id == template.path_template_id
    assert assignment.provider_path_ref == "spacecraft-1-downlink"

    assert {:ok, %{applied_count: 0, skipped_count: 1, failed_count: 0}} =
             LinkSetup.apply_link_template(
               context.organization_id,
               context.mission_id,
               template,
               [spacecraft],
               application_attrs
             )

    assert {:ok, %LinkAssignment{lifecycle_state: :deleted}} =
             LinkAssignmentStore.delete(
               context.organization_id,
               context.mission_id,
               assignment.link_assignment_id,
               %{"reason" => "retired"}
             )

    assert LinkAssignmentStore.list(context.organization_id, context.mission_id) == []
  end

  test "rejects incomplete shared-link configuration", context do
    assert {:error, "Link name is required."} =
             LinkSetup.create_shared_link(context.organization_id, context.mission_id, %{
               "display_name" => " "
             })
  end
end
