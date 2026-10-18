defmodule Cadence.Reads.Spacecraft.ProfileForm do
  @moduledoc "Host-owned spacecraft profile creation projection."
  alias Cadence.Applications.ApplicationDefinition
  alias Cadence.Spacecraft.ProfileCreation
  import Cadence.Reads.Spacecraft.Presentation

  def new(mission) do
    definitions = ProfileCreation.available_applications()

    %{
      "page" => %{
        "id" => "spacecraft-profile-new-page",
        "title" => "New Spacecraft Profile",
        "subtitle" =>
          "Captures the byte-interpretation contract shared across spacecraft of the same kind — downlink and uplink protocols, frame parameters, and which platform applications run.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb("Profiles", profiles_path(mission)),
          breadcrumb("New Spacecraft Profile", nil)
        ]
      },
      "form" => profile_form(mission),
      "options" => profile_form_options(),
      "applications" => Enum.map(definitions, &application_option/1)
    }
  end

  defp profile_form(mission) do
    %{
      "id" => "spacecraft-profile-form",
      "sections" => %{
        "identity" => section("spacecraft-profile-identity-section", "01", "Identity", nil),
        "protocols" => section("spacecraft-profile-protocols-section", "02", "Protocols", nil),
        "frame_parameters" =>
          section(
            "spacecraft-profile-frame-parameters-section",
            "03",
            "Frame Parameters",
            "How the spacecraft frames the bytes it transmits. Fields adapt to the selected downlink protocol."
          ),
        "applications" =>
          section("spacecraft-profile-applications-section", "04", "Applications", nil)
      },
      "fields" => %{
        "display_name" =>
          field(
            "spacecraft-profile-display-name",
            "spacecraft_type[display_name]",
            "text",
            "Display Name",
            "",
            true
          ),
        "downlink_protocol" =>
          field(
            "spacecraft-profile-downlink-protocol",
            "spacecraft_type[downlink_protocol]",
            "select",
            "Downlink Protocol",
            "tm",
            true
          ),
        "uplink_protocol" =>
          field(
            "spacecraft-profile-uplink-protocol",
            "spacecraft_type[uplink_protocol]",
            "select",
            "Uplink Protocol",
            "tc",
            true
          ),
        "frame_size" =>
          field(
            "spacecraft-profile-frame-size",
            "spacecraft_type[frame_size]",
            "number",
            "Transfer Frame Size (bytes)",
            "",
            true
          ),
        "secondary_header_length" =>
          field(
            "spacecraft-profile-secondary-header-length",
            "spacecraft_type[secondary_header_length]",
            "number",
            "Secondary Header Length (bytes, 0 if absent)",
            "0",
            false
          ),
        "insert_zone_length" =>
          field(
            "spacecraft-profile-insert-zone-length",
            "spacecraft_type[insert_zone_length]",
            "number",
            "Insert Zone Length (bytes, 0 if absent)",
            "0",
            false
          ),
        "truncated_primary_header" =>
          field(
            "spacecraft-profile-truncated-primary-header",
            "spacecraft_type[truncated_primary_header]",
            "select",
            "Truncated Primary Header",
            "false",
            false
          ),
        "ocf_length" =>
          field(
            "spacecraft-profile-ocf-length",
            "spacecraft_type[ocf_length]",
            "select",
            "Operational Control Field",
            "0",
            false
          ),
        "applications" => %{
          "id" => "spacecraft-profile-application-options",
          "name" => "spacecraft_type[applications]",
          "value" => %{}
        }
      },
      "actions" => %{
        "submit" => %{"id" => "create-spacecraft-profile-button", "label" => "Create Profile"},
        "cancel" => %{
          "id" => "cancel-spacecraft-profile-link",
          "label" => "Cancel",
          "href" => profiles_path(mission)
        }
      }
    }
  end

  defp section(id, number, title, description),
    do: %{"id" => id, "number" => number, "title" => title, "description" => description}

  defp profile_form_options,
    do: %{
      "downlink_protocols" => [
        %{"label" => "TM", "value" => "tm"},
        %{"label" => "AOS", "value" => "aos"},
        %{"label" => "USLP", "value" => "uslp"}
      ],
      "uplink_protocols" => [
        %{"label" => "TC", "value" => "tc"},
        %{"label" => "USLP", "value" => "uslp"}
      ],
      "truncated_primary_headers" => [
        %{"label" => "No", "value" => "false"},
        %{"label" => "Yes", "value" => "true"}
      ],
      "operational_control_fields" => [
        %{"label" => "Not present", "value" => "0"},
        %{"label" => "Present (4 bytes)", "value" => "4"}
      ],
      "frame_fields" => %{
        "secondary_header_length" => ["tm"],
        "insert_zone_length" => ["aos"],
        "truncated_primary_header" => ["uslp"]
      }
    }

  defp application_option(%ApplicationDefinition{} = definition),
    do: %{
      "id" => "spacecraft-profile-application-#{definition.application_key}",
      "key" => definition.application_key,
      "name" => "spacecraft_type[applications][#{definition.application_key}]",
      "value" => "1",
      "label" => definition.display_name,
      "description" => definition.description,
      "available" => ApplicationDefinition.available?(definition),
      "availability_label" =>
        if(ApplicationDefinition.available?(definition), do: nil, else: "Roadmap")
    }
end
