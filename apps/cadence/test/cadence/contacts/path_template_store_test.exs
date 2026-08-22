defmodule Cadence.Contacts.PathTemplateStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.PathTemplateStore
  alias Cadence.Contacts.ProfileStore
  alias Cadence.Contacts.ProviderProfile
  alias Cadence.Contacts.TransportProfile

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-path-template-store-#{suffix}"
    mission_id = "mission-path-template-store-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "persists, resolves, versions, lists, and tombstones path templates", context do
    assert {:ok, %ProviderProfile{} = provider_profile} =
             ProfileStore.persist_provider_profile(
               context.organization_id,
               ProviderProfile.new(%{
                 provider_profile_id: "provider-1",
                 mission_id: context.mission_id,
                 adapter_key: :tcp_socket,
                 configuration: %{"mode" => "listen"}
               })
             )

    assert {:ok, %TransportProfile{} = transport_profile} =
             ProfileStore.persist_transport_profile(
               context.organization_id,
               TransportProfile.new(%{
                 transport_profile_id: "transport-1",
                 mission_id: context.mission_id,
                 family_key: :uplink_gateway,
                 target_scope: :path,
                 configuration: %{"route" => "primary"}
               })
             )

    template =
      PathTemplate.new(%{
        path_template_id: "template-1",
        mission_id: context.mission_id,
        path_id: "path-1",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: "discarded-for-reusable-template",
        provider_profile_ids: [provider_profile.provider_profile_id],
        transport_profile_ids: [transport_profile.transport_profile_id],
        metadata: %{"owner" => "ops"}
      })

    assert {:ok, %PathTemplate{version: 1} = persisted} =
             PathTemplateStore.persist(context.organization_id, template)

    assert persisted.organization_id == context.organization_id
    assert persisted.source_endpoint_ref == nil

    assert persisted.provider_profile_refs == [
             %{"provider_profile_id" => provider_profile.provider_profile_id, "version" => 1}
           ]

    assert persisted.transport_profile_refs == [
             %{"transport_profile_id" => transport_profile.transport_profile_id, "version" => 1}
           ]

    assert {:ok, path} = PathTemplateStore.resolve(persisted)
    assert Enum.map(path.provider_bindings, & &1.provider_binding_id) == ["provider-1"]
    assert Enum.map(path.transport_bindings, & &1.transport_binding_id) == ["transport-1"]

    assert {:ok, %PathTemplate{version: 2} = versioned} =
             PathTemplateStore.version(
               context.organization_id,
               context.mission_id,
               template.path_template_id,
               %{path_id: "path-2", metadata: %{"reviewed" => true}}
             )

    assert versioned.path_id == "path-2"
    assert versioned.metadata == %{"owner" => "ops", "reviewed" => true}

    assert [%PathTemplate{version: 2}] =
             PathTemplateStore.list(context.organization_id, context.mission_id)

    assert Enum.map(
             PathTemplateStore.list_versions(
               context.organization_id,
               context.mission_id,
               template.path_template_id
             ),
             & &1.version
           ) == [2, 1]

    assert {:ok, %PathTemplate{version: 3, lifecycle_state: :deleted}} =
             PathTemplateStore.delete(
               context.organization_id,
               context.mission_id,
               template.path_template_id,
               %{"reason" => "retired"}
             )

    assert {:error, :contact_path_template_not_found} =
             PathTemplateStore.fetch(
               context.organization_id,
               context.mission_id,
               template.path_template_id
             )

    assert {:ok, %PathTemplate{version: 1}} =
             PathTemplateStore.fetch_version(
               context.organization_id,
               context.mission_id,
               template.path_template_id,
               1
             )
  end
end
