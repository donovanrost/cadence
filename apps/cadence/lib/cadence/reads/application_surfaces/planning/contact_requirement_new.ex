defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactRequirementNew do
  @moduledoc "Initial requirement declaration data for an authorized mission surface."

  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.Planning.Form
  alias Cadence.SpacecraftStore

  def load(%Scope{} = scope, mission) do
    spacecraft = SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)
    starts_at = DateTime.utc_now() |> DateTime.add(900, :second) |> DateTime.truncate(:second)

    params = %{
      "spacecraft_id" =>
        case spacecraft do
          [first | _] -> first.spacecraft_id
          [] -> ""
        end,
      "contact_intent" => "payload_downlink",
      "earliest_start" => Calendar.strftime(starts_at, "%Y-%m-%dT%H:%M:%S"),
      "latest_end" =>
        Calendar.strftime(DateTime.add(starts_at, 86_400, :second), "%Y-%m-%dT%H:%M:%S"),
      "success_measure" => "minimum_data_volume",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "1000000000",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "allowed_providers" => "",
      "excluded_providers" => "",
      "allowed_stations" => "",
      "excluded_stations" => "",
      "rationale" => ""
    }

    form = Form.new("contact_requirement", params)

    %{
      page: page_dto(),
      journey: journey_dto(form),
      form: contact_requirement_form_dto(form, spacecraft, nil),
      actions: actions_dto(mission)
    }
  end

  defp page_dto do
    %{
      id: "ops-contact-requirement-new-page",
      eyebrow: "Need / outcome-first declaration",
      heading: "What does the mission need?",
      description:
        "Describe success and the acceptable horizon. Provider, station, and route choices remain planning concerns—not part of the need itself."
    }
  end

  defp journey_dto(form) do
    success_measure = Form.value(form, :success_measure)

    %{
      outcome: %{
        id: "contact-requirement-outcome-section",
        step: "01",
        title: "Mission outcome",
        copy: "The operator-readable reason this contact must exist."
      },
      horizon: %{
        id: "contact-requirement-horizon-section",
        step: "02",
        title: "Acceptable horizon",
        copy: "All times are coordinated universal time."
      },
      advanced: %{
        id: "requirement-advanced-constraints",
        title: "Advanced constraints",
        copy: "Optional provider and station boundaries"
      },
      rationale: %{id: "contact-requirement-rationale-section"},
      progressive: %{
        minimum_data_volume: %{
          id: "requirement-minimum-data-volume-section",
          visible: success_measure == "minimum_data_volume",
          visible_for: ["minimum_data_volume"]
        },
        minimum_duration: %{
          id: "requirement-minimum-duration-section",
          visible: success_measure in ["minimum_duration", "minimum_data_volume"],
          visible_for: ["minimum_duration", "minimum_data_volume"]
        }
      }
    }
  end

  defp contact_requirement_form_dto(form, spacecraft, form_error) do
    %{
      id: "contact-requirement-form",
      fields: %{
        spacecraft_id: %{
          id: "requirement-spacecraft",
          name: "contact_requirement[spacecraft_id]",
          type: "select",
          label: "Spacecraft",
          required: true,
          value: Form.value(form, :spacecraft_id),
          options: Enum.map(spacecraft, &%{label: &1.display_name, value: &1.spacecraft_id})
        },
        contact_intent: %{
          id: "requirement-intent",
          name: "contact_requirement[contact_intent]",
          type: "select",
          label: "Contact intent",
          required: false,
          value: Form.value(form, :contact_intent),
          options: [
            %{label: "Payload downlink", value: "payload_downlink"},
            %{label: "Health and safety", value: "health_and_safety"},
            %{label: "TT&C maintenance", value: "ttc_maintenance"},
            %{label: "Commissioning", value: "commissioning"}
          ]
        },
        success_measure: %{
          id: "requirement-success-measure",
          name: "contact_requirement[success_measure]",
          type: "select",
          label: "Success means",
          required: false,
          value: Form.value(form, :success_measure),
          options: [
            %{label: "Minimum data volume", value: "minimum_data_volume"},
            %{label: "Minimum contact duration", value: "minimum_duration"},
            %{label: "Number of contacts", value: "contact_count"},
            %{label: "Any eligible contact", value: "any_contact"}
          ]
        },
        priority: %{
          id: "requirement-priority",
          name: "contact_requirement[priority]",
          type: "select",
          label: "Operational priority",
          required: false,
          value: Form.value(form, :priority),
          options: [
            %{label: "Routine", value: "routine"},
            %{label: "High", value: "high"},
            %{label: "Critical", value: "critical"}
          ]
        },
        earliest_start:
          datetime_field_dto(
            form,
            :earliest_start,
            "requirement-earliest-start",
            "Earliest start (UTC)"
          ),
        latest_end:
          datetime_field_dto(
            form,
            :latest_end,
            "requirement-latest-end",
            "Latest end (UTC)"
          ),
        minimum_data_volume_bytes:
          number_field_dto(
            form,
            :minimum_data_volume_bytes,
            "requirement-minimum-data-volume",
            "Minimum data volume (bytes)",
            "1"
          ),
        minimum_duration_seconds:
          number_field_dto(
            form,
            :minimum_duration_seconds,
            "requirement-minimum-duration",
            "Minimum window duration (seconds)",
            "1"
          ),
        preferred_duration_seconds:
          number_field_dto(
            form,
            :preferred_duration_seconds,
            "requirement-preferred-duration",
            "Preferred window duration (seconds)",
            "1"
          ),
        contact_count:
          number_field_dto(
            form,
            :contact_count,
            "requirement-contact-count",
            "Required contact count",
            "1"
          ),
        minimum_separation_seconds:
          number_field_dto(
            form,
            :minimum_separation_seconds,
            "requirement-minimum-separation",
            "Minimum separation (seconds)",
            "0"
          ),
        allowed_providers:
          text_field_dto(
            form,
            :allowed_providers,
            "requirement-allowed-providers",
            "Allowed provider IDs",
            "provider-a, provider-b"
          ),
        excluded_providers:
          text_field_dto(
            form,
            :excluded_providers,
            "requirement-excluded-providers",
            "Excluded provider IDs",
            "provider-c"
          ),
        allowed_stations:
          text_field_dto(
            form,
            :allowed_stations,
            "requirement-allowed-stations",
            "Allowed station refs",
            "station-a, station-b"
          ),
        excluded_stations:
          text_field_dto(
            form,
            :excluded_stations,
            "requirement-excluded-stations",
            "Excluded station refs",
            "station-c"
          ),
        rationale: %{
          id: "requirement-rationale",
          name: "contact_requirement[rationale]",
          type: "textarea",
          label: "Operator rationale",
          required: true,
          value: Form.value(form, :rationale),
          placeholder: "Why this outcome and horizon are operationally important",
          maxlength: "2000"
        }
      },
      error:
        form_error &&
          %{
            id: "contact-requirement-form-error",
            message: form_error
          }
    }
  end

  defp actions_dto(mission) do
    requirements_path = "/missions/#{mission.mission_id}/ops/requirements"

    %{
      back: %{
        id: "contact-requirements-back-link",
        label: "Requirements",
        href: requirements_path,
        icon: "hero-arrow-left"
      },
      cancel: %{
        id: "cancel-contact-requirement",
        label: "Cancel",
        href: requirements_path
      },
      submit: %{id: "save-contact-requirement", label: "Declare need"}
    }
  end

  defp datetime_field_dto(form, field, id, label) do
    %{
      id: id,
      name: "contact_requirement[#{field}]",
      type: "datetime-local",
      label: label,
      required: true,
      value: Form.value(form, field)
    }
  end

  defp number_field_dto(form, field, id, label, minimum) do
    %{
      id: id,
      name: "contact_requirement[#{field}]",
      type: "number",
      label: label,
      required: false,
      value: Form.value(form, field),
      min: minimum
    }
  end

  defp text_field_dto(form, field, id, label, placeholder) do
    %{
      id: id,
      name: "contact_requirement[#{field}]",
      type: "text",
      label: label,
      required: false,
      value: Form.value(form, field),
      placeholder: placeholder
    }
  end
end
