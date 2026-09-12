defmodule Cadence.Reads.Applications.SpacecraftInstallations do
  @moduledoc false
  alias Cadence.Applications.HostContext
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications.{Inventory, InventoryItem}
  alias Cadence.Reads.Spacecraft.PinnedProfile
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType

  def load(scope, host_context, mission) do
    with {:ok, spacecraft} <- fetch_host_spacecraft(mission, host_context),
         {:ok, profile} <- PinnedProfile.load(mission, spacecraft),
         {:ok, items} <-
           Inventory.declared(
             scope,
             host_context,
             profile_declarations(profile),
             ExtensionCatalog.applications_for_scope(:spacecraft)
           ) do
      {:ok,
       %{"presentation" => applications_presentation_dto(mission, spacecraft, profile, items)}}
    end
  end

  defp applications_presentation_dto(mission, spacecraft, profile, items) do
    %{
      "root" => %{
        "attrs" => %{"id" => "spacecraft-applications-page", "class" => "space-y-6"}
      },
      "header" => %{
        "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
        "body" => %{"attrs" => %{}},
        "content" => %{"attrs" => %{}},
        "breadcrumbs" => %{
          "attrs" => %{"class" => "flex items-center gap-2 text-xs text-base-content/60"},
          "items" => [
            breadcrumb(mission.display_name, mission_path(mission)),
            breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
            breadcrumb(
              spacecraft.display_name,
              spacecraft_path(mission, spacecraft.spacecraft_id)
            ),
            breadcrumb("Applications", nil)
          ]
        },
        "title" => %{"attrs" => %{}, "text" => "Applications"},
        "subtitle" => %{
          "attrs" => %{"class" => "mt-1 text-sm text-base-content/70"},
          "text" => "Manage the applications declared by the pinned spacecraft profile."
        },
        "actions" => %{
          "attrs" => %{},
          "readiness" => %{
            "attrs" => %{"href" => readiness_path(mission, spacecraft)},
            "text" => "Readiness"
          }
        }
      },
      "component" => %{"attrs" => %{"id" => "spacecraft-applications-component"}},
      "profile" => applications_profile(mission, spacecraft, profile),
      "applications" => Enum.map(items, &application_card(&1, mission, spacecraft))
    }
  end

  defp applications_profile(mission, spacecraft, nil),
    do: %{
      "kind" => "missing",
      "id" => "spacecraft-applications-no-profile",
      "label" => "Spacecraft Profile",
      "title" => "No profile selected",
      "description" =>
        "Select a Spacecraft Profile before installing profile-declared applications.",
      "action" => %{
        "label" => "Select profile",
        "path" => "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/identity"
      }
    }

  defp applications_profile(_mission, _spacecraft, profile),
    do: %{
      "kind" => "pinned",
      "id" => "spacecraft-applications-profile",
      "label" => "Pinned Profile",
      "display_name" => profile.display_name,
      "version" => profile.version,
      "status" => %{"tone" => "ready", "label" => "Current"}
    }

  defp application_card(%InventoryItem{} = item, mission, spacecraft) do
    card_id = "spacecraft-application-#{safe_key(item.application_key)}"

    %{
      "id" => card_id,
      "application_key" => item.application_key,
      "application_version" => item.application_version,
      "display_name" => item.display_name,
      "description" => item.description,
      "lifecycle_state" => item.lifecycle_state && to_string(item.lifecycle_state),
      "installable" => item.installable?,
      "manageable" => item.manageable?,
      "uninstallable" => item.uninstallable?,
      "scope_label" => "Application",
      "manage_path" => "#{applications_path(mission, spacecraft)}/#{item.application_key}",
      "status" => %{
        "state" => to_string(item.status.state),
        "label" => item.status.label,
        "tone" => to_string(item.status.tone),
        "facts" =>
          Enum.map(item.status.facts, fn fact ->
            %{"id" => fact.id, "label" => fact.label, "value" => fact.value}
          end)
      },
      "install_action" =>
        if(item.installable? and not item.manageable?,
          do: lifecycle_action("#{card_id}-install", "install", "Install", "primary"),
          else: nil
        ),
      "disable_action" =>
        if(item.manageable?,
          do: lifecycle_action("#{card_id}-disable", "disable", "Disable", "secondary"),
          else: nil
        ),
      "uninstall_action" =>
        if(item.uninstallable?,
          do: lifecycle_action("#{card_id}-uninstall", "uninstall", "Uninstall", "danger"),
          else: nil
        ),
      "unavailable_message" =>
        if(item.installable?,
          do: nil,
          else: "This application is not available at the spacecraft scope."
        )
    }
  end

  defp profile_declarations(nil), do: %{}
  defp profile_declarations(%SpacecraftType{applications: applications}), do: applications

  defp fetch_host_spacecraft(mission, %HostContext{
         placement: :spacecraft,
         spacecraft_id: spacecraft_id
       }) do
    SpacecraftStore.fetch_spacecraft(mission.organization_id, mission.mission_id, spacecraft_id)
  end

  defp mission_path(mission), do: "/missions/#{mission.mission_id}"
  defp spacecraft_path(mission, nil), do: "#{mission_path(mission)}/spacecraft"
  defp spacecraft_path(mission, id), do: "#{spacecraft_path(mission, nil)}/#{id}"

  defp readiness_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/readiness"

  defp applications_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/applications"

  defp breadcrumb(label, href), do: %{"label" => label, "href" => href}
  defp safe_key(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]+/, "-")

  defp lifecycle_action(id, action_id, label, variant),
    do: %{
      "id" => id,
      "action_id" => action_id,
      "label" => label,
      "variant" => variant,
      "effect" => "durable",
      "execution" => "immediate",
      "confirmation" => nil
    }
end
