defmodule Cadence.Reads.Spacecraft.Overview do
  @moduledoc "Core spacecraft overview independent of frontend delivery."
  alias Cadence.Reads.Applications.{Inventory, InventoryItem}
  alias Cadence.Reads.Spacecraft.Context
  alias Cadence.Spacecraft, as: SpacecraftAsset
  import Cadence.Reads.Spacecraft.Presentation

  def load(scope, mission, id) do
    with {:ok, %{spacecraft: spacecraft, profile: profile, applications: applications}} <-
           Context.load(scope, mission, id) do
      case applications do
        {:ok, items} ->
          {:ok, presentation(mission, spacecraft, profile, items)}

        {:error, _} ->
          {:ok, unavailable_inventory(presentation(mission, spacecraft, profile, []))}
      end
    end
  end

  def presentation(mission, spacecraft, profile, applications) do
    app_summary = Inventory.summary(applications)

    %{
      "page" => %{
        "id" => "spacecraft-show-page",
        "header" => %{
          "title" => spacecraft.display_name,
          "breadcrumbs" => [
            navigation_item(mission.display_name, mission_path(mission)),
            navigation_item("Spacecraft", spacecraft_path(mission, nil)),
            navigation_item(spacecraft.display_name, nil)
          ],
          "title_suffix" =>
            if(spacecraft.scid,
              do: %{"set" => true, "label" => "SCID #{spacecraft.scid}"},
              else: %{"set" => false, "label" => "SCID not set"}
            )
        }
      },
      "profile_binding" => profile_binding(mission, spacecraft, profile),
      "applications" =>
        application_inventory(mission, spacecraft, profile, applications, app_summary),
      "workflow_cards" => workflow_cards(mission, spacecraft, profile, app_summary),
      "overview" => overview(spacecraft, mission)
    }
  end

  defp profile_binding(mission, spacecraft, nil),
    do: %{
      "id" => "spacecraft-profile-binding",
      "eyebrow" => "Spacecraft Profile",
      "bound" => false,
      "title" =>
        if(spacecraft.spacecraft_type_id,
          do: "Pinned profile unavailable",
          else: "No profile selected"
        ),
      "description" =>
        "Review the spacecraft profile binding to define its byte-interpretation contract.",
      "version" => nil,
      "protocols" => [],
      "status" =>
        if(spacecraft.spacecraft_type_id,
          do: status("blocked", "Unavailable"),
          else: status("attention", "Unbound")
        ),
      "view_profile_href" => nil,
      "profile_action" => %{
        "label" => "Select profile",
        "href" => identity_path(mission, spacecraft)
      }
    }

  defp profile_binding(mission, spacecraft, profile),
    do: %{
      "id" => "spacecraft-profile-binding",
      "eyebrow" => "Pinned Profile",
      "bound" => true,
      "title" => profile.display_name,
      "description" => nil,
      "version" => "v#{profile.version}",
      "protocols" => [
        %{"label" => "Downlink", "value" => to_string(profile.downlink_protocol)},
        %{"label" => "Uplink", "value" => to_string(profile.uplink_protocol)}
      ],
      "status" => status("ready", "Pinned"),
      "view_profile_href" => profile_path(mission, profile.spacecraft_type_id),
      "profile_action" => %{
        "label" => "Change profile",
        "href" => identity_path(mission, spacecraft)
      }
    }

  defp application_inventory(mission, spacecraft, nil, _items, _summary),
    do: %{
      "id" => "spacecraft-applications",
      "list_id" => "spacecraft-applications-list",
      "visible" => true,
      "title" => "Applications",
      "description" => "Select a Spacecraft Profile before managing applications.",
      "empty" => true,
      "empty_state" => "No applications are declared.",
      "rows" => [],
      "view_action" => %{
        "label" => "View applications",
        "href" => applications_path(mission, spacecraft)
      }
    }

  defp application_inventory(mission, spacecraft, _profile, items, summary),
    do: %{
      "id" => "spacecraft-applications",
      "list_id" => "spacecraft-applications-list",
      "visible" => true,
      "title" => "Applications",
      "description" => "Profile-declared applications for this spacecraft.",
      "empty" => items == [],
      "empty_state" => "No applications are declared by the pinned profile.",
      "rows" => Enum.map(items, &application_row(&1, mission, spacecraft)),
      "view_action" => %{
        "label" => "View applications",
        "href" => applications_path(mission, spacecraft)
      },
      "summary" => summary.label
    }

  defp application_row(%InventoryItem{} = item, mission, spacecraft),
    do: %{
      "id" => "spacecraft-application-#{safe_key(item.application_key)}",
      "application_key" => item.application_key,
      "display_name" => item.display_name,
      "status" => status(to_string(item.status.tone), item.status.label),
      "manage_href" =>
        if(item.manageable?,
          do: "#{applications_path(mission, spacecraft)}/#{item.application_key}",
          else: nil
        )
    }

  defp workflow_cards(mission, spacecraft, profile, summary),
    do: [
      %{
        "id" => "spacecraft-workflow-identity",
        "title" => "Identity",
        "value" => if(spacecraft.scid, do: "SCID #{spacecraft.scid}", else: "SCID not set"),
        "description" => "Durable spacecraft identity and profile binding.",
        "status" =>
          status(
            if(spacecraft.scid, do: "ready", else: "attention"),
            if(spacecraft.scid, do: "Ready", else: "Attention")
          ),
        "action" => %{"label" => "Edit identity", "href" => identity_path(mission, spacecraft)}
      },
      %{
        "id" => "spacecraft-workflow-applications",
        "title" => "Applications",
        "value" => summary.label,
        "description" => "Profile-declared applications and lifecycle state.",
        "status" => status(to_string(summary.tone), summary.label),
        "action" => %{
          "label" => "Manage applications",
          "href" => applications_path(mission, spacecraft)
        }
      },
      %{
        "id" => "spacecraft-workflow-readiness",
        "title" => "Readiness",
        "value" => if(profile, do: "Profile bound", else: "Setup needed"),
        "description" => "Review the operational setup before commanding.",
        "status" => status("info", "Review setup"),
        "action" => %{
          "label" => "Review readiness",
          "href" => readiness_path(mission, spacecraft)
        }
      }
    ]

  defp overview(spacecraft, mission),
    do: %{
      "title" => "Overview",
      "scid" => %{"label" => "SCID", "value" => scid_label(spacecraft)},
      "display_name" => %{"label" => "Display Name", "value" => spacecraft.display_name},
      "spacecraft_id" => %{"label" => "Spacecraft ID", "value" => spacecraft.spacecraft_id},
      "mission" => %{
        "label" => "Mission",
        "value" => mission.display_name,
        "href" => mission_path(mission)
      },
      "organization_id" => %{"label" => "Organization ID", "value" => mission.organization_id},
      "metadata_json" =>
        if(spacecraft.metadata == %{},
          do: nil,
          else: Jason.encode!(spacecraft.metadata, pretty: true)
        )
    }

  defp status(tone, label), do: %{"tone" => tone, "label" => label}

  defp unavailable_inventory(data) do
    data
    |> update_in(
      ["applications"],
      &Map.merge(&1, %{
        "empty_state" => "Application inventory could not be loaded.",
        "description" => "Application inventory unavailable."
      })
    )
    |> update_in(["workflow_cards"], &Enum.map(&1, fn card -> unavailable_card(card) end))
  end

  defp unavailable_card(%{"id" => id} = card)
       when id in ["spacecraft-workflow-applications", "spacecraft-workflow-readiness"],
       do:
         Map.merge(card, %{"status" => status("blocked", "Unavailable"), "value" => "Unavailable"})

  defp unavailable_card(card), do: card

  defp readiness_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/readiness"

  defp applications_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/applications"

  defp scid_label(%SpacecraftAsset{scid: nil}), do: "Not set"
  defp scid_label(%SpacecraftAsset{scid: scid}), do: to_string(scid)
  defp safe_key(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]+/, "-")
end
