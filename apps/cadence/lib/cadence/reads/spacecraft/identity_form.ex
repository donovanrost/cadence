defmodule Cadence.Reads.Spacecraft.IdentityForm do
  @moduledoc "Core spacecraft creation and identity form projections."
  alias Cadence.{SpacecraftStore, SpacecraftTypeStore}
  import Cadence.Reads.Spacecraft.Presentation

  def edit(mission, spacecraft_id) do
    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             mission.organization_id,
             mission.mission_id,
             spacecraft_id
           ),
         do: {:ok, edit_presentation(mission, spacecraft)}
  end

  def new(mission) do
    types = SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)

    %{
      "page" => %{
        "id" => "spacecraft-new-page",
        "heading" => "New Spacecraft",
        "subtitle" =>
          "Register a spacecraft for this mission. Optionally start with a protocol preset.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb("New Spacecraft", nil)
        ]
      },
      "form" => spacecraft_form(mission, "new", nil),
      "profile_options" => profile_options(mission, types, nil)
    }
  end

  defp edit_presentation(mission, spacecraft) do
    types = SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)

    %{
      "page" => %{
        "id" => "spacecraft-edit-page",
        "heading" => "Spacecraft Identity",
        "subtitle" => "Update the name and spacecraft identifier for #{spacecraft.display_name}.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb(spacecraft.display_name, spacecraft_path(mission, spacecraft.spacecraft_id)),
          breadcrumb("Identity", nil)
        ]
      },
      "form" => spacecraft_form(mission, "edit", spacecraft),
      "profile_options" => profile_options(mission, types, spacecraft)
    }
  end

  defp spacecraft_form(mission, kind, spacecraft) do
    %{
      "id" => spacecraft_form_id(kind),
      "profile_version" => spacecraft && spacecraft.spacecraft_type_version,
      "configuration_href" => configuration_href(mission, spacecraft),
      "sections" => %{
        "identity" => %{
          "id" => identity_section_id(kind),
          "number" => "01",
          "title" => "Identity"
        },
        "profile" => %{
          "id" => profile_section_id(kind),
          "number" => "02",
          "title" => "Communications"
        }
      },
      "fields" => %{
        "display_name" =>
          field(
            display_name_field_id(kind),
            "spacecraft[display_name]",
            "text",
            "Display Name",
            (spacecraft && spacecraft.display_name) || "",
            true
          ),
        "scid" =>
          field(
            scid_field_id(kind),
            "spacecraft[scid]",
            "text",
            "SCID",
            scid_value(spacecraft),
            false
          ),
        "spacecraft_type_id" =>
          field(
            profile_field_id(kind),
            "spacecraft[spacecraft_type_id]",
            "select",
            "Protocol preset",
            (spacecraft && spacecraft.spacecraft_type_id) || "",
            false
          )
      },
      "actions" => %{
        "submit" => %{
          "id" => submit_button_id(kind),
          "label" => submit_button_label(kind)
        },
        "cancel" => %{
          "id" => cancel_link_id(kind),
          "label" => "Cancel",
          "href" => spacecraft_path(mission, nil)
        }
      }
    }
  end

  defp configuration_href(mission, %{metadata: metadata} = spacecraft)
       when is_map_key(metadata, "spacecraft_configuration_revision_id"),
       do: spacecraft_path(mission, spacecraft.spacecraft_id) <> "?section=communications"

  defp configuration_href(_mission, _spacecraft), do: nil

  defp spacecraft_form_id("edit"), do: "spacecraft-edit-form"
  defp spacecraft_form_id(_kind), do: "spacecraft-form"

  defp identity_section_id("edit"), do: "spacecraft-edit-identity-section"
  defp identity_section_id(_kind), do: "spacecraft-identity-section"

  defp profile_section_id("edit"), do: "spacecraft-edit-profile-section"
  defp profile_section_id(_kind), do: "spacecraft-profile-section"

  defp display_name_field_id("edit"), do: "spacecraft-edit-display-name"
  defp display_name_field_id(_kind), do: "spacecraft-display-name"

  defp scid_field_id("edit"), do: "spacecraft-edit-scid"
  defp scid_field_id(_kind), do: "spacecraft-scid"

  defp profile_field_id("edit"), do: "spacecraft-edit-profile"
  defp profile_field_id(_kind), do: "spacecraft-profile"

  defp submit_button_id("edit"), do: "save-spacecraft-identity-button"
  defp submit_button_id(_kind), do: "create-spacecraft-button"

  defp submit_button_label("edit"), do: "Save Identity"
  defp submit_button_label(_kind), do: "Create Spacecraft"

  defp cancel_link_id("edit"), do: "cancel-spacecraft-identity-link"
  defp cancel_link_id(_kind), do: "cancel-spacecraft-link"

  defp profile_options(mission, types, spacecraft) do
    types = Enum.reject(types, &Map.has_key?(&1.metadata, "spacecraft_configuration_revision_id"))

    options =
      Enum.map(
        types,
        &%{
          "label" => "#{&1.display_name} (v#{&1.version})",
          "value" => &1.spacecraft_type_id,
          "version" => &1.version
        }
      )

    current =
      if spacecraft && spacecraft.spacecraft_type_id do
        %{
          "label" =>
            "#{spacecraft.spacecraft_type_id} (v#{spacecraft.spacecraft_type_version}, current pin)",
          "value" => spacecraft.spacecraft_type_id,
          "version" => spacecraft.spacecraft_type_version
        }
      end

    options =
      if current &&
           not Enum.any?(
             options,
             &(&1["value"] == current["value"] and &1["version"] == current["version"])
           ), do: [current | options], else: options

    %{
      "options" => [%{"label" => "None", "value" => "", "version" => nil} | options],
      "empty" => types == [],
      "empty_state" => %{
        "message" => "No spacecraft profiles are defined.",
        "action" => %{
          "id" => "create-spacecraft-profile-link",
          "label" => "Create one",
          "href" => "#{profiles_path(mission)}/new"
        },
        "suffix" => ""
      }
    }
  end

  defp scid_value(nil), do: ""

  defp scid_value(spacecraft),
    do: if(is_nil(spacecraft.scid), do: "", else: to_string(spacecraft.scid))
end
