defmodule Cadence.Reads.Applications.MissionInstallations do
  @moduledoc false
  alias Cadence.Applications.{ActionConfirmation, HostContext, LifecycleActions}
  alias Cadence.ExtensionCatalog
  alias Cadence.Reads.Applications.{Inventory, InventoryItem}

  def load(scope, mission_id) do
    host_context = HostContext.mission(mission_id)

    with {:ok, applications} <-
           Inventory.catalog(
             scope,
             host_context,
             ExtensionCatalog.available_applications_for_scope(:mission)
           ) do
      {:ok,
       %{
         "presentation" => %{
           "root" => %{"attrs" => %{"id" => "mission-applications-page", "class" => "space-y-6"}},
           "header" => %{
             "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
             "body" => %{"attrs" => %{}},
             "content" => %{"attrs" => %{}},
             "breadcrumbs" => mission_breadcrumbs("Applications", mission_id),
             "title" => %{
               "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
               "text" => "Applications"
             },
             "subtitle" => %{
               "attrs" => %{"class" => "mt-1 max-w-3xl text-sm text-base-content/70"},
               "text" =>
                 "Install mission-scoped product capabilities and open their host-rendered workspaces."
             }
           },
           "applications_component" => %{
             "attrs" => %{"id" => "mission-applications-component"},
             "props" => %{
               "applications" => Enum.map(applications, &application_row(&1, mission_id))
             }
           }
         }
       }}
    end
  end

  defp application_row(%InventoryItem{} = application, mission_id) do
    card_id = "mission-application-#{safe_key(application.application_key)}"

    %{
      "id" => card_id,
      "application_key" => application.application_key,
      "application_version" => application.application_version,
      "display_name" => application.display_name,
      "description" => application.description,
      "lifecycle_state" => atom_string(application.lifecycle_state),
      "installable" => application.installable?,
      "manageable" => application.manageable?,
      "uninstallable" => application.uninstallable?,
      "scope_label" => "Mission Application",
      "manage_path" => "/missions/#{mission_id}/applications/#{application.application_key}",
      "status" => status_dto(application.status),
      "install_action" =>
        if(application.installable? and not application.manageable?,
          do: lifecycle_action("install", application.lifecycle_state, card_id)
        ),
      "disable_action" =>
        if(application.manageable?,
          do: lifecycle_action("disable", application.lifecycle_state, card_id)
        ),
      "uninstall_action" =>
        if(application.uninstallable?,
          do: lifecycle_action("uninstall", application.lifecycle_state, card_id)
        ),
      "unavailable_message" =>
        if(application.installable?,
          do: nil,
          else: "This application is not available for installation in this deployment."
        )
    }
  end

  defp status_dto(status) when is_binary(status),
    do: %{"tone" => status, "label" => status_label(status)}

  defp status_dto(status) do
    %{
      "state" => atom_string(status.state),
      "label" => status.label,
      "tone" => atom_string(status.tone),
      "facts" =>
        Enum.map(status.facts, &%{"id" => &1.id, "label" => &1.label, "value" => &1.value})
    }
  end

  defp status_label("ready"), do: "Ready"
  defp status_label("attention"), do: "Needs Work"
  defp status_label("blocked"), do: "Missing"
  defp status_label(other), do: String.capitalize(other)

  defp lifecycle_action(action_id, state, card_id) do
    {:ok, action} = LifecycleActions.fetch(action_id)
    confirmation = action.confirmation

    %{
      "id" => "#{action_id}-#{card_id}",
      "action_id" => action.action_id,
      "label" => if(action_id == "install", do: install_label(state), else: action.label),
      "variant" => atom_string(action.button_variant),
      "effect" => atom_string(action.effect),
      "execution" => atom_string(action.execution),
      "confirmation" => confirmation && confirmation_dto(confirmation)
    }
  end

  defp confirmation_dto(%ActionConfirmation{} = confirmation),
    do: %{
      "title" => confirmation.title,
      "message" => confirmation.message,
      "confirm_label" => confirmation.confirm_label,
      "tone" => atom_string(confirmation.tone),
      "prompt" => ActionConfirmation.prompt(confirmation)
    }

  defp install_label(:disabled), do: "Enable"
  defp install_label(:uninstalled), do: "Reinstall"
  defp install_label(:installed), do: "Upgrade"
  defp install_label(_state), do: "Install"

  defp mission_breadcrumbs(current, mission_id),
    do: %{
      "attrs" => %{
        "aria-label" => "Breadcrumb",
        "class" =>
          "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
      },
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{"attrs" => navigate_attrs(mission_href(mission_id)), "text" => "Mission"},
          "current" => nil
        },
        %{
          "key" => "current",
          "separator" => separator(),
          "link" => nil,
          "current" => %{"attrs" => %{"class" => "text-primary/90"}, "text" => current}
        }
      ]
    }

  defp separator,
    do: %{"attrs" => %{"class" => "text-base-content/20", "aria-hidden" => "true"}, "text" => "/"}

  defp navigate_attrs(href),
    do: %{"data-phx-link" => "redirect", "data-phx-link-state" => "push", "href" => href}

  defp mission_href(mission_id), do: "/missions/#{mission_id}"

  defp safe_key(key), do: String.replace(key, ~r/[^A-Za-z0-9_-]+/, "-")
  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_string(value), do: value
end
