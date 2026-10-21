defmodule Cadence.Reads.Missions.Overview do
  @moduledoc "Core mission overview and spacecraft readiness presentation."
  alias Cadence.{Missions, SpacecraftStore}

  @readiness_preview_size 25

  def load(organization_id, mission_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id) do
      spacecraft = SpacecraftStore.list_spacecraft(organization_id, mission_id)
      endpoints = Cadence.SourceEndpoints.list_source_endpoints(organization_id, mission_id)
      templates = Cadence.Contacts.list_path_templates(organization_id, mission_id)
      assignments = Cadence.Contacts.list_link_assignments(organization_id, mission_id)

      readiness =
        Enum.map(spacecraft, &readiness_row(&1, endpoints, templates, assignments, mission_id))

      ready = Enum.count(readiness, &(&1["status"] == "ready"))
      missing_scid = Enum.count(spacecraft, &is_nil(&1.scid))
      missing_path = Enum.count(readiness, &(&1["status"] == "attention"))
      issues = Enum.count(readiness, &(&1["status"] != "ready"))

      {:ok,
       %{
         "overview" => %{
           "mission" => %{
             "eyebrow" => "Mission",
             "display_name" => mission.display_name,
             "slug" => mission.slug
           },
           "readiness_cards" => [
             readiness_card(
               "Ready Spacecraft",
               ready,
               if(ready == 0, do: "attention", else: "ready"),
               "Spacecraft with SCID and identity configured."
             ),
             readiness_card(
               "Need SCID",
               missing_scid,
               if(missing_scid == 0, do: "ready", else: "blocked"),
               "Spacecraft that cannot be resolved from incoming frames yet."
             ),
             readiness_card(
               "Need Link",
               missing_path,
               if(missing_path == 0, do: "ready", else: "attention"),
               "Spacecraft with identity configured but no provider link."
             )
           ],
           "setup" => %{
             "eyebrow" => "Spacecraft Readiness",
             "title" => "Configure spacecraft identity and select a spacecraft profile",
             "description" => readiness_description(length(readiness)),
             "issue_count" => issues,
             "status" => status_dto(if(issues == 0, do: "ready", else: "attention")),
             "empty" => readiness == [],
             "empty_state" => %{
               "title" => "No spacecraft have been registered for this mission yet.",
               "action_label" => "Add the first spacecraft",
               "action_href" => "/missions/#{mission_id}/spacecraft/new"
             }
           }
         },
         "spacecraft_readiness" => Enum.take(readiness, @readiness_preview_size)
       }}
    end
  end

  defp readiness_description(count) when count > @readiness_preview_size do
    "Showing the first #{@readiness_preview_size} of #{count} spacecraft. " <>
      "Readiness totals cover the entire mission. Open Spacecraft to browse and filter the full fleet."
  end

  defp readiness_description(_count) do
    "Each row shows whether a spacecraft can be identified from incoming frames and has a profile that defines its byte-interpretation contract."
  end

  defp readiness_card(title, value, tone, description),
    do: %{
      "title" => title,
      "value" => value,
      "status" => status_dto(tone),
      "description" => description
    }

  defp readiness_row(spacecraft, endpoints, templates, assignments, mission_id) do
    endpoint = Enum.find(endpoints, &(&1.spacecraft_id == spacecraft.spacecraft_id))
    endpoint_id = endpoint && endpoint.source_endpoint_id
    assigned = Enum.filter(assignments, &(&1.spacecraft_id == spacecraft.spacecraft_id))

    available = available_template_count(templates)
    provider_paths = provider_path_count(assigned)
    status = readiness_status(spacecraft, endpoint, provider_paths)

    issue =
      if status == "ready",
        do: "Spacecraft identity and downlink routes are configured.",
        else: readiness_issue(spacecraft, endpoint, available)

    path_label = readiness_path_label(endpoint, provider_paths, available)

    %{
      "id" => spacecraft.spacecraft_id,
      "__dom_id" => "spacecraft-readiness-#{spacecraft.spacecraft_id}",
      "actions_id" => "#{spacecraft.spacecraft_id}-readiness-actions",
      "spacecraft_display_name" => spacecraft.display_name,
      "spacecraft_id" => spacecraft.spacecraft_id,
      "scid_label" =>
        if(is_nil(spacecraft.scid), do: "Not set", else: Integer.to_string(spacecraft.scid)),
      "endpoint_label" => if(is_nil(endpoint), do: "Missing", else: "Telemetry identity"),
      "endpoint_ref_label" => endpoint_id || "Not created",
      "path_label" => path_label,
      "path_detail" => readiness_path_detail(provider_paths, available),
      "status" => status,
      "status_label" =>
        %{"ready" => "Ready", "attention" => "Needs link", "blocked" => "Needs identity"}[status],
      "issue" => issue,
      "primary_action" => primary_action(status, spacecraft),
      "primary_action_href" =>
        "/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness",
      "view_spacecraft_href" => "/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
    }
  end

  defp available_template_count(templates) do
    Enum.count(
      templates,
      &(&1.direction == :downlink and is_nil(&1.source_endpoint_ref) and
          &1.provider_profile_refs != [])
    )
  end

  defp provider_path_count(assigned),
    do: Enum.count(assigned, &(&1.direction == :downlink and &1.provider_profile_refs != []))

  defp readiness_status(spacecraft, endpoint, provider_paths) do
    cond do
      is_nil(spacecraft.scid) -> "blocked"
      is_nil(endpoint) -> "blocked"
      provider_paths > 0 -> "ready"
      true -> "attention"
    end
  end

  defp readiness_issue(spacecraft, endpoint, available) do
    cond do
      is_nil(spacecraft.scid) ->
        "Set SCID so Cadence can identify this spacecraft from TM transfer frames."

      is_nil(endpoint) ->
        "Sync the internal telemetry identity for this spacecraft."

      available > 0 ->
        "Assign an available downlink route to this spacecraft."

      true ->
        "Create a provider-backed downlink routing rule for this spacecraft."
    end
  end

  defp readiness_path_label(endpoint, provider_paths, available) do
    cond do
      is_nil(endpoint) ->
        "No downlink route"

      provider_paths > 0 ->
        "#{provider_paths} downlink route#{if(provider_paths == 1, do: "", else: "s")}"

      available > 0 ->
        "Available to assign"

      true ->
        "No downlink route"
    end
  end

  defp readiness_path_detail(provider_paths, available) do
    cond do
      provider_paths > 0 ->
        "#{provider_paths} provider-backed"

      available > 0 ->
        "#{available} available mission template#{if(available == 1, do: "", else: "s")}"

      true ->
        "Not configured"
    end
  end

  defp primary_action("ready", _spacecraft), do: "Review readiness"
  defp primary_action("attention", _spacecraft), do: "Assign link"

  defp primary_action("blocked", spacecraft),
    do: if(is_nil(spacecraft.scid), do: "Set SCID", else: "Sync identity")

  defp status_dto(status), do: %{"tone" => status, "label" => status_label(status)}
  defp status_label("ready"), do: "Ready"
  defp status_label("attention"), do: "Needs Work"
  defp status_label("blocked"), do: "Missing"
  defp status_label(other), do: String.capitalize(other)
end
