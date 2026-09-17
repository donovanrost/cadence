defmodule Cadence.Reads.Spacecraft.Profiles do
  @moduledoc "Core spacecraft profile directory and immutable version details."

  alias Cadence.SpacecraftTypeStore
  import Cadence.Reads.Spacecraft.Presentation

  def directory(mission) do
    profiles =
      SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)
      |> Enum.reject(&Map.has_key?(&1.metadata, "spacecraft_configuration_revision_id"))

    %{
      "presentation" => %{
        "root" => %{"attrs" => %{"id" => "spacecraft-profiles-page", "class" => "space-y-6"}},
        "header" => profile_header(mission, length(profiles)),
        "empty_state" =>
          if(profiles == [],
            do:
              empty_state(
                "No Spacecraft Profiles",
                "Optionally define a shared protocol preset to reuse across spacecraft."
              ),
            else: nil
          ),
        "card" => if(profiles == [], do: nil, else: profile_card(mission, profiles))
      }
    }
  end

  def detail(mission, profile_id) do
    with {:ok, profile} <-
           SpacecraftTypeStore.fetch_spacecraft_type(
             mission.organization_id,
             mission.mission_id,
             profile_id
           ) do
      versions =
        SpacecraftTypeStore.list_spacecraft_type_versions(
          mission.organization_id,
          mission.mission_id,
          profile_id
        )

      {:ok,
       %{
         "profile" => profile_details(profile),
         "navigation" => %{
           "breadcrumbs" => [
             navigation_item(mission.display_name, mission_path(mission)),
             navigation_item("Spacecraft", spacecraft_path(mission, nil)),
             navigation_item("Profiles", profiles_path(mission)),
             navigation_item(profile.display_name, nil)
           ]
         },
         "labels" => %{
           "byte_interpretation" => "Byte Interpretation",
           "applications" => "Applications",
           "version_history" => "Version History",
           "downlink_protocol" => "Downlink Protocol",
           "uplink_protocol" => "Uplink Protocol",
           "packet_protocol" => "Packet Protocol",
           "lifecycle" => "Lifecycle",
           "version" => "Version",
           "downlink" => "Downlink",
           "uplink" => "Uplink",
           "frame_parameters" => "Frame Parameters",
           "no_applications" => "No applications declared."
         },
         "versions" => Enum.map(versions, &version_details/1)
       }}
    end
  end

  defp profile_header(mission, count),
    do:
      Map.merge(
        header("Spacecraft Profiles", "#{count} defined profiles shared across spacecraft."),
        %{
          "actions" => %{
            "attrs" => %{},
            "new_profile" => %{
              "id" => "new-spacecraft-profile-link",
              "label" => "New Profile",
              "href" => "#{profiles_path(mission)}/new"
            }
          }
        }
      )

  defp empty_state(title, description), do: %{"title" => title, "description" => description}

  defp profile_card(mission, profiles),
    do: %{
      "attrs" => %{
        "id" => "spacecraft-profiles-card",
        "class" => "card border border-base-300 bg-base-200"
      },
      "body" => %{"attrs" => %{"class" => "card-body p-0"}},
      "list_component" => %{"attrs" => %{"id" => "spacecraft-profiles-list-component"}},
      "rows" =>
        Enum.map(
          profiles,
          &%{
            "id" => "spacecraft-profile-#{&1.spacecraft_type_id}",
            "display_name" => &1.display_name,
            "version" => "v#{&1.version}",
            "downlink_protocol" => String.upcase(to_string(&1.downlink_protocol)),
            "uplink_protocol" => String.upcase(to_string(&1.uplink_protocol)),
            "applications" => application_summary(&1.applications),
            "href" => profile_path(mission, &1.spacecraft_type_id)
          }
        )
    }

  defp profile_details(profile),
    do: %{
      "id" => "spacecraft-profile-#{profile.spacecraft_type_id}",
      "profile_id" => profile.spacecraft_type_id,
      "display_name" => profile.display_name,
      "version" => "v#{profile.version}",
      "lifecycle" => to_string(profile.lifecycle_state),
      "downlink_protocol" => String.upcase(to_string(profile.downlink_protocol)),
      "uplink_protocol" => String.upcase(to_string(profile.uplink_protocol)),
      "packet_protocol" => to_string(profile.packet_protocol),
      "frame_parameters" =>
        Enum.map(
          Enum.sort_by(profile.frame_parameters, fn {key, _} -> to_string(key) end),
          fn {key, value} ->
            %{
              "id" => "spacecraft-profile-frame-parameter-#{key}",
              "label" => humanize(key),
              "value" => to_string(value)
            }
          end
        ),
      "applications" =>
        Enum.map(Enum.sort(Map.keys(profile.applications)), fn key ->
          %{"id" => "spacecraft-profile-application-#{key}", "label" => humanize(key)}
        end)
    }

  defp version_details(profile),
    do: %{
      "id" => "spacecraft-profile-version-#{profile.spacecraft_type_id}-#{profile.version}",
      "version" => "v#{profile.version}",
      "lifecycle" => to_string(profile.lifecycle_state),
      "downlink_protocol" => String.upcase(to_string(profile.downlink_protocol)),
      "uplink_protocol" => String.upcase(to_string(profile.uplink_protocol))
    }
end
