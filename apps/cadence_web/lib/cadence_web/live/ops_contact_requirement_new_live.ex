defmodule CadenceWeb.OpsContactRequirementNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.ContactRequirements
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    spacecraft =
      Cadence.SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)

    starts_at = DateTime.utc_now() |> DateTime.add(15 * 60, :second) |> DateTime.truncate(:second)

    form_params = %{
      "spacecraft_id" =>
        spacecraft |> List.first() |> then(&if(&1, do: &1.spacecraft_id, else: "")),
      "contact_intent" => "payload_downlink",
      "earliest_start" => datetime_local(starts_at),
      "latest_end" => starts_at |> DateTime.add(24 * 60 * 60, :second) |> datetime_local(),
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

    {:ok,
     socket
     |> assign(:page_title, "Declare Contact Need")
     |> assign(:ops_nav_item, :requirements)
     |> assign(:spacecraft, spacecraft)
     |> assign(:page, page_dto())
     |> assign(:actions, actions_dto(mission))
     |> assign_form_state(form_params, nil)}
  end

  @impl true
  def handle_event("validate", %{"contact_requirement" => params}, socket) do
    {:noreply, assign_form_state(socket, params, nil)}
  end

  def handle_event("save", %{"contact_requirement" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, attrs} <- requirement_attrs(params),
         {:ok, requirement, _version} <-
           ContactRequirements.create(scope, mission.mission_id, attrs) do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
       )}
    else
      {:error, reason} ->
        {:noreply, assign_form_state(socket, params, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-requirement-new-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_requirement_new"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp assign_form_state(socket, params, form_error) do
    form = to_form(params, as: :contact_requirement)

    socket
    |> assign(:journey, journey_dto(form))
    |> assign(
      :contact_requirement_form,
      contact_requirement_form_dto(form, socket.assigns.spacecraft, form_error)
    )
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
    success_measure = string_form_value(form, :success_measure)

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
          value: string_form_value(form, :spacecraft_id),
          options: Enum.map(spacecraft, &%{label: &1.display_name, value: &1.spacecraft_id})
        },
        contact_intent: %{
          id: "requirement-intent",
          name: "contact_requirement[contact_intent]",
          type: "select",
          label: "Contact intent",
          required: false,
          value: string_form_value(form, :contact_intent),
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
          value: string_form_value(form, :success_measure),
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
          value: string_form_value(form, :priority),
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
          value: string_form_value(form, :rationale),
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
    requirements_path = ~p"/missions/#{mission.mission_id}/ops/requirements"

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
      value: string_form_value(form, field)
    }
  end

  defp number_field_dto(form, field, id, label, minimum) do
    %{
      id: id,
      name: "contact_requirement[#{field}]",
      type: "number",
      label: label,
      required: false,
      value: string_form_value(form, field),
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
      value: string_form_value(form, field),
      placeholder: placeholder
    }
  end

  defp string_form_value(form, field) do
    case Map.get(form.params, Atom.to_string(field)) do
      value when is_binary(value) -> value
      nil -> ""
      value -> to_string(value)
    end
  end

  defp requirement_attrs(params) do
    with {:ok, earliest_start} <- parse_datetime(params["earliest_start"]),
         {:ok, latest_end} <- parse_datetime(params["latest_end"]),
         {:ok, minimum_duration} <- optional_integer(params["minimum_duration_seconds"]),
         {:ok, preferred_duration} <- optional_integer(params["preferred_duration_seconds"]),
         {:ok, minimum_volume} <- optional_integer(params["minimum_data_volume_bytes"]),
         {:ok, contact_count} <- positive_integer(params["contact_count"], 1),
         {:ok, separation} <- nonnegative_integer(params["minimum_separation_seconds"], 0) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         service_direction: :downlink,
         contact_intent: params["contact_intent"],
         earliest_start: earliest_start,
         latest_end: latest_end,
         success_measure: params["success_measure"],
         minimum_duration_seconds: minimum_duration,
         preferred_duration_seconds: preferred_duration,
         minimum_data_volume_bytes: minimum_volume,
         contact_count: contact_count,
         minimum_separation_seconds: separation,
         priority: params["priority"],
         provider_constraints_document: %{
           "allowed" => refs(params["allowed_providers"]),
           "excluded" => refs(params["excluded_providers"])
         },
         station_constraints_document: %{
           "allowed" => refs(params["allowed_stations"]),
           "excluded" => refs(params["excluded_stations"])
         },
         policy_constraints_document: %{},
         approval_policy_document: %{"mode" => "manual"},
         rationale: params["rationale"] || "",
         metadata: %{"source" => "ops_contact_requirement_form"}
       }}
    end
  end

  defp parse_datetime(value) do
    case NaiveDateTime.from_iso8601(value || "") do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      _error -> {:error, :invalid_requirement_time}
    end
  end

  defp optional_integer(value) when value in [nil, ""], do: {:ok, nil}

  defp optional_integer(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_requirement_number}
    end
  end

  defp positive_integer(value, default) when value in [nil, ""], do: {:ok, default}

  defp positive_integer(value, _default) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _other -> {:error, :invalid_requirement_number}
    end
  end

  defp nonnegative_integer(value, default) when value in [nil, ""], do: {:ok, default}

  defp nonnegative_integer(value, _default) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _other -> {:error, :invalid_requirement_number}
    end
  end

  defp refs(value) do
    value
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")

  defp error_message({:invalid_contact_requirement, message}), do: message
  defp error_message(:invalid_requirement_time), do: "Enter a valid UTC start and end time."

  defp error_message(:invalid_requirement_number),
    do: "Numeric outcomes must be positive whole numbers."

  defp error_message(_reason),
    do: "Cadence could not declare this need. Review the outcome and constraints."
end
