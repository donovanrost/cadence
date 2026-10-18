defmodule Cadence.Reads.Spacecraft.Readiness do
  @moduledoc "Host readiness composition with capability-owned data contributions."
  alias Cadence.Reads.Applications.{Inventory, InventoryItem}
  alias Cadence.Reads.Spacecraft.{Context, ReadinessContributions}
  alias Cadence.Spacecraft, as: SpacecraftAsset
  import Cadence.Reads.Spacecraft.Presentation

  def load(scope, mission, id) do
    with {:ok, %{spacecraft: spacecraft, profile: profile, applications: applications}} <-
           Context.load(scope, mission, id) do
      case applications do
        {:ok, items} ->
          {:ok, presentation(scope, mission, spacecraft, profile, items)}

        {:error, _} ->
          {:ok, unavailable_inventory(presentation(scope, mission, spacecraft, profile, []))}
      end
    end
  end

  def presentation(scope, mission, spacecraft, profile, applications) do
    summary = Inventory.summary(applications)
    contributions = ReadinessContributions.load(scope, mission, spacecraft, applications)

    identity_status =
      if is_integer(spacecraft.scid),
        do: status("ready", "Ready"),
        else: status("attention", "Attention")

    profile_status =
      cond do
        profile -> status("ready", "Pinned")
        spacecraft.spacecraft_type_id -> status("blocked", "Pinned profile unavailable")
        true -> status("attention", "Unbound")
      end

    %{
      "context" => %{
        "organizationId" => mission.organization_id,
        "missionId" => mission.mission_id,
        "spacecraftId" => spacecraft.spacecraft_id
      },
      "contributions" => contributions,
      "page" => %{
        "id" => "spacecraft-readiness-page",
        "title" => "Readiness",
        "title_suffix" => "· #{spacecraft.display_name}",
        "subtitle" =>
          "A bounded view of the identity, profile, applications, and routing setup required for operations.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb(
            spacecraft.display_name,
            spacecraft_path(mission, spacecraft.spacecraft_id)
          ),
          breadcrumb("Readiness", nil)
        ],
        "status" =>
          aggregate(
            [identity_status, profile_status, status(to_string(summary.tone), summary.label)] ++
              Enum.map(contributions, & &1["status"])
          )
      },
      "panels" => [
        readiness_panel(
          "spacecraft-readiness-identity",
          "Identity",
          identity_status,
          "Durable spacecraft identity.",
          [%{"label" => "SCID", "value" => scid_label(spacecraft)}],
          "Edit Identity",
          identity_path(mission, spacecraft)
        ),
        readiness_panel(
          "spacecraft-readiness-profile",
          "Profile",
          profile_status,
          "Pinned byte-interpretation contract.",
          [
            %{
              "label" => "Pinned Profile",
              "value" => (profile && profile.display_name) || "None"
            }
          ],
          if(profile, do: "Change Profile", else: "Select Profile"),
          identity_path(mission, spacecraft)
        ),
        readiness_panel(
          "spacecraft-readiness-applications",
          "Applications",
          status(to_string(summary.tone), summary.label),
          "Profile-declared applications and their installation state.",
          [],
          "Review Applications",
          applications_path(mission, spacecraft),
          %{
            "id" => "spacecraft-readiness-application-list",
            "empty_state" => %{
              "id" => "spacecraft-readiness-application-empty",
              "description" => "No applications are declared by the pinned profile."
            }
          }
        )
      ],
      "applications" => Enum.map(applications, &readiness_application/1)
    }
  end

  defp readiness_panel(
         id,
         title,
         status,
         description,
         details,
         action_label,
         action_href,
         application_list \\ nil
       ),
       do: %{
         "id" => id,
         "title" => title,
         "status" => status,
         "description" => description,
         "details" => details,
         "action" => %{"label" => action_label, "href" => action_href},
         "application_list" => application_list
       }

  defp readiness_application(%InventoryItem{} = item),
    do: %{
      "id" => "spacecraft-readiness-application-#{safe_key(item.application_key)}",
      "application_key" => item.application_key,
      "display_name" => item.display_name,
      "status" => status(to_string(item.status.tone), item.status.label)
    }

  defp unavailable_inventory(data) do
    data
    |> put_in(["page", "status"], status("blocked", "Review setup"))
    |> update_in(["panels"], &Enum.map(&1, fn panel -> unavailable_panel(panel) end))
  end

  defp unavailable_panel(%{"id" => "spacecraft-readiness-applications"} = panel) do
    panel
    |> Map.put("status", status("blocked", "Unavailable"))
    |> Map.put("description", "Application inventory could not be loaded.")
    |> put_in(
      ["application_list", "empty_state", "description"],
      "Application inventory unavailable."
    )
  end

  defp unavailable_panel(panel), do: panel

  defp aggregate(statuses) do
    tone =
      Enum.find(["blocked", "attention", "info", "ready"], fn tone ->
        Enum.any?(statuses, &(&1["tone"] == tone))
      end)

    status(tone, if(tone == "ready", do: "Checks ready", else: "Review setup"))
  end

  defp status(tone, label), do: %{"tone" => tone, "label" => label}

  defp applications_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/applications"

  defp scid_label(%SpacecraftAsset{scid: nil}), do: "Not set"
  defp scid_label(%SpacecraftAsset{scid: scid}), do: to_string(scid)
  defp safe_key(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]+/, "-")
end
