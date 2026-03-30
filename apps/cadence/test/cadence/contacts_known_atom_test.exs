defmodule Cadence.ContactsKnownAtomTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.{
    ContactAction,
    Path,
    PathTemplate,
    ProviderBinding,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    TransportBinding,
    TransportProfile
  }

  test "hydrates contact path enums from persisted string values" do
    path =
      Path.new(%{
        "path_id" => "downlink-path-alpha",
        "direction" => "downlink",
        "selection_role" => "selected",
        "provider_bindings" => [
          %{
            "provider_binding_id" => "provider-binding-alpha",
            "adapter_key" => "tcp_socket",
            "configuration" => %{"mode" => "listen"}
          }
        ],
        "transport_bindings" => [
          %{
            "transport_binding_id" => "transport-binding-alpha",
            "family_key" => "uplink_gateway",
            "target_scope" => "path",
            "configuration" => %{"transport_profile" => "tc"}
          }
        ]
      })

    assert path.direction == :downlink
    assert path.selection_role == :selected
    assert [%ProviderBinding{adapter_key: :tcp_socket}] = path.provider_bindings

    assert [%TransportBinding{family_key: :uplink_gateway, target_scope: :path}] =
             path.transport_bindings
  end

  test "hydrates realized and scheduled contacts from persisted string values" do
    realized_contact =
      RealizedContact.new(%{
        :mission_id => "mission-alpha",
        :paths => [
          %{
            "path_id" => "downlink-path-alpha",
            "direction" => "downlink",
            "selection_role" => "selected"
          }
        ],
        "clock_mode" => "live",
        "lifecycle_state" => "active"
      })

    scheduled_contact =
      ScheduledContact.new(%{
        :mission_id => "mission-alpha",
        :starts_at => DateTime.utc_now(),
        "paths" => [
          %{
            "path_id" => "uplink-path-alpha",
            "direction" => "uplink",
            "selection_role" => "candidate"
          }
        ],
        "lifecycle_state" => "realized"
      })

    assert realized_contact.clock_mode == :live
    assert realized_contact.lifecycle_state == :active
    assert [%Path{direction: :downlink, selection_role: :selected}] = realized_contact.paths

    assert scheduled_contact.lifecycle_state == :realized
    assert [%Path{direction: :uplink, selection_role: :candidate}] = scheduled_contact.paths
  end

  test "hydrates versioned contact config resources from persisted string values" do
    provider_profile =
      ProviderProfile.new(%{
        :mission_id => "mission-alpha",
        "adapter_key" => "tcp_socket",
        "lifecycle_state" => "active"
      })

    transport_profile =
      TransportProfile.new(%{
        :mission_id => "mission-alpha",
        "family_key" => "heartbeat_monitor",
        "target_scope" => "transport",
        "lifecycle_state" => "deleted"
      })

    path_template =
      PathTemplate.new(%{
        :mission_id => "mission-alpha",
        "direction" => "downlink",
        "selection_role" => "contributing",
        "lifecycle_state" => "active"
      })

    assert provider_profile.adapter_key == :tcp_socket
    assert provider_profile.lifecycle_state == :active

    assert transport_profile.family_key == :heartbeat_monitor
    assert transport_profile.target_scope == :transport
    assert transport_profile.lifecycle_state == :deleted

    assert path_template.direction == :downlink
    assert path_template.selection_role == :contributing
    assert path_template.lifecycle_state == :active
  end

  test "hydrates contact actions from persisted string values" do
    action =
      ContactAction.new(%{
        :mission_id => "mission-alpha",
        "action_kind" => "realized_contact_ended_early"
      })

    assert action.action_kind == :realized_contact_ended_early
  end
end
