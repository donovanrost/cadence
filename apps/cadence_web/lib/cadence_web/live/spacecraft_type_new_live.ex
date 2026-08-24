defmodule CadenceWeb.SpacecraftTypeNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Applications.ApplicationDefinition
  alias Cadence.ExtensionCatalog
  alias Cadence.SpacecraftType
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    applications = ExtensionCatalog.applications_for_scope(:spacecraft)

    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft Profile")
     |> assign(:nav_item, :spacecraft)
     |> assign(:page, page_dto(mission))
     |> assign(:form, form_dto(empty_form_params(), mission))
     |> assign(:options, options_dto())
     |> assign(:applications, applications_dto(applications))}
  end

  @impl true
  def handle_event("validate", %{"spacecraft_type" => params}, socket) do
    {:noreply, assign(socket, :form, form_dto(params, socket.assigns.current_mission))}
  end

  @impl true
  def handle_event("save", %{"spacecraft_type" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    socket = assign(socket, :form, form_dto(params, mission))

    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, downlink_protocol} <- protocol(params["downlink_protocol"], :downlink),
         {:ok, uplink_protocol} <- protocol(params["uplink_protocol"], :uplink),
         {:ok, frame_parameters} <- frame_parameters(downlink_protocol, params),
         {:ok, applications} <- applications_from_params(params) do
      type =
        SpacecraftType.new(%{
          mission_id: mission.mission_id,
          display_name: display_name,
          downlink_protocol: downlink_protocol,
          uplink_protocol: uplink_protocol,
          packet_protocol: :space_packet,
          frame_parameters: frame_parameters,
          applications: applications
        })

      case Cadence.SpacecraftTypeStore.persist_spacecraft_type(scope.organization_id, type) do
        {:ok, persisted} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{persisted.spacecraft_type_id}"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    else
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-profile-new-component"
        v-component="SpacecraftTypeNew"
        page={@page}
        form={@form}
        options={@options}
        applications={@applications}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
        class="space-y-6 max-w-2xl"
      />
    </Layouts.app>
    """
  end

  defp page_dto(mission) do
    %{
      id: "spacecraft-profile-new-page",
      title: "New Spacecraft Profile",
      subtitle:
        "Captures the byte-interpretation contract shared across spacecraft of the same kind — downlink and uplink protocols, frame parameters, and which platform applications run.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Spacecraft", href: ~p"/missions/#{mission.mission_id}/spacecraft"},
        %{
          label: "Spacecraft Profiles",
          href: ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
        },
        %{label: "New Spacecraft Profile", href: nil}
      ]
    }
  end

  defp form_dto(params, mission) do
    %{
      id: "spacecraft-profile-form",
      sections: %{
        identity: section_dto("spacecraft-profile-identity-section", "01", "Identity"),
        protocols:
          section_dto(
            "spacecraft-profile-protocols-section",
            "02",
            "Data Link Protocols"
          ),
        frame_parameters:
          section_dto(
            "spacecraft-profile-frame-parameters-section",
            "03",
            "Downlink Frame Parameters",
            "How the spacecraft frames the bytes it transmits. Fields adapt to the selected downlink protocol."
          ),
        applications:
          section_dto(
            "spacecraft-profile-applications-section",
            "04",
            "Applications",
            "Which platform applications run for spacecraft using this profile. Per-application configuration is set on each spacecraft."
          )
      },
      fields: %{
        display_name:
          field_dto(
            :display_name,
            "text",
            "Display Name",
            true,
            string_param(params, "display_name")
          ),
        downlink_protocol:
          field_dto(
            :downlink_protocol,
            "select",
            "Downlink Protocol",
            true,
            string_param(params, "downlink_protocol")
          ),
        uplink_protocol:
          field_dto(
            :uplink_protocol,
            "select",
            "Uplink Protocol",
            true,
            string_param(params, "uplink_protocol")
          ),
        frame_size:
          field_dto(
            :frame_size,
            "number",
            "Transfer Frame Size (bytes)",
            true,
            string_param(params, "frame_size")
          ),
        secondary_header_length:
          field_dto(
            :secondary_header_length,
            "number",
            "Secondary Header Length (bytes, 0 if absent)",
            false,
            string_param(params, "secondary_header_length")
          ),
        insert_zone_length:
          field_dto(
            :insert_zone_length,
            "number",
            "Insert Zone Length (bytes, 0 if absent)",
            false,
            string_param(params, "insert_zone_length")
          ),
        truncated_primary_header:
          field_dto(
            :truncated_primary_header,
            "select",
            "Truncated Primary Header",
            false,
            string_param(params, "truncated_primary_header")
          ),
        ocf_length:
          field_dto(
            :ocf_length,
            "select",
            "Operational Control Field",
            false,
            string_param(params, "ocf_length")
          ),
        applications: %{
          id: "spacecraft-profile-application-options",
          name: "spacecraft_type[applications]",
          value: application_values(params)
        }
      },
      actions: %{
        submit: %{id: "create-spacecraft-profile-button", label: "Create Profile"},
        cancel: %{
          id: "cancel-spacecraft-profile-link",
          label: "Cancel",
          href: ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
        }
      }
    }
  end

  defp section_dto(id, number, title, description \\ nil) do
    %{id: id, number: number, title: title, description: description}
  end

  defp field_dto(field, type, label, required, value) do
    field_name = Atom.to_string(field)

    %{
      id: "spacecraft_type_#{field_name}",
      name: "spacecraft_type[#{field_name}]",
      type: type,
      label: label,
      required: required,
      value: value
    }
  end

  defp options_dto do
    %{
      downlink_protocols: options_dto(downlink_protocol_options()),
      uplink_protocols: options_dto(uplink_protocol_options()),
      truncated_primary_headers: [option_dto("No", "false"), option_dto("Yes", "true")],
      operational_control_fields: [
        option_dto("Not present", "0"),
        option_dto("Present (4 bytes)", "4")
      ],
      frame_fields: %{
        secondary_header_length: visible_downlink_protocols(:secondary_header_length),
        insert_zone_length: visible_downlink_protocols(:insert_zone_length),
        truncated_primary_header: visible_downlink_protocols(:truncated_primary_header)
      }
    }
  end

  defp options_dto(options), do: Enum.map(options, fn {label, value} -> option_dto(label, value) end)

  defp option_dto(label, value), do: %{label: label, value: value}

  defp downlink_protocol_options do
    [{"TM", "tm"}, {"AOS", "aos"}, {"USLP", "uslp"}]
  end

  defp uplink_protocol_options do
    [{"TC", "tc"}, {"USLP", "uslp"}]
  end

  defp visible_downlink_protocols(field) do
    Enum.filter(["tm", "aos", "uslp"], &frame_field_visible?(&1, field))
  end

  defp frame_field_visible?(downlink_protocol, :secondary_header_length) do
    downlink_protocol in ["tm", :tm]
  end

  defp frame_field_visible?(downlink_protocol, :insert_zone_length) do
    downlink_protocol in ["aos", :aos]
  end

  defp frame_field_visible?(downlink_protocol, :truncated_primary_header) do
    downlink_protocol in ["uslp", :uslp]
  end

  defp applications_dto(applications) do
    Enum.map(applications, fn application ->
      key = application.application_key
      available? = application_available?(application)

      %{
        id: "spacecraft-profile-application-#{key}",
        key: key,
        name: "spacecraft_type[applications][#{key}]",
        value: "1",
        label: application.display_name,
        description: application.description,
        available: available?,
        availability_label: if(available?, do: nil, else: "Roadmap")
      }
    end)
  end

  defp empty_form_params do
    %{
      "display_name" => "",
      "downlink_protocol" => "tm",
      "uplink_protocol" => "tc",
      "frame_size" => "",
      "secondary_header_length" => "0",
      "insert_zone_length" => "0",
      "truncated_primary_header" => "false",
      "ocf_length" => "0",
      "applications" => %{}
    }
  end

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp string_param(_params, _key), do: ""

  defp application_values(params) when is_map(params) do
    case Map.get(params, "applications") do
      applications when is_map(applications) ->
        applications
        |> Map.keys()
        |> Enum.filter(&(is_binary(&1) and application_checked?(params, &1)))
        |> Map.new(&{&1, "1"})

      _other ->
        %{}
    end
  end

  defp application_values(_params), do: %{}

  defp application_checked?(params, key) do
    case Map.get(params, "applications") do
      %{} = applications -> Map.has_key?(applications, key)
      _other -> false
    end
  end

  defp protocol("tm", :downlink), do: {:ok, :tm}
  defp protocol("aos", :downlink), do: {:ok, :aos}
  defp protocol("uslp", :downlink), do: {:ok, :uslp}
  defp protocol("tc", :uplink), do: {:ok, :tc}
  defp protocol("uslp", :uplink), do: {:ok, :uslp}
  defp protocol(_, :downlink), do: {:error, "Downlink protocol is invalid."}
  defp protocol(_, :uplink), do: {:error, "Uplink protocol is invalid."}

  defp frame_parameters(:tm, params) do
    with {:ok, frame_size} <- positive_integer(params["frame_size"], "Frame size"),
         {:ok, secondary_header_length} <-
           non_negative_integer(params["secondary_header_length"], "Secondary header length"),
         {:ok, ocf_length} <- ocf_length(params["ocf_length"]) do
      {:ok,
       %{
         "frame_size" => frame_size,
         "secondary_header_length" => secondary_header_length,
         "ocf_length" => ocf_length
       }}
    end
  end

  defp frame_parameters(:aos, params) do
    with {:ok, frame_size} <- positive_integer(params["frame_size"], "Frame size"),
         {:ok, insert_zone_length} <-
           non_negative_integer(params["insert_zone_length"], "Insert zone length"),
         {:ok, ocf_length} <- ocf_length(params["ocf_length"]) do
      {:ok,
       %{
         "frame_size" => frame_size,
         "insert_zone_length" => insert_zone_length,
         "ocf_length" => ocf_length
       }}
    end
  end

  defp frame_parameters(:uslp, params) do
    with {:ok, frame_size} <- positive_integer(params["frame_size"], "Frame size"),
         {:ok, truncated} <- boolean(params["truncated_primary_header"]),
         {:ok, ocf_length} <- ocf_length(params["ocf_length"]) do
      {:ok,
       %{
         "frame_size" => frame_size,
         "truncated_primary_header" => truncated,
         "ocf_length" => ocf_length
       }}
    end
  end

  defp applications_from_params(params) do
    available_by_param =
      ExtensionCatalog.available_applications_for_scope(:spacecraft)
      |> Map.new(fn application ->
        {application.application_key, application.application_key}
      end)

    applications =
      params
      |> application_values()
      |> Enum.reduce(%{}, fn {key, _value}, acc ->
        case Map.fetch(available_by_param, key) do
          {:ok, application_key} -> Map.put(acc, application_key, %{})
          :error -> acc
        end
      end)

    {:ok, applications}
  end

  defp required_text(value, message) do
    case normalize(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp application_available?(application) do
    ApplicationDefinition.available?(application)
  end

  defp positive_integer(value, label) do
    case parse_integer(value) do
      {:ok, integer} when integer > 0 -> {:ok, integer}
      _ -> {:error, "#{label} must be a positive integer."}
    end
  end

  defp non_negative_integer(value, label) do
    case parse_integer(value) do
      {:ok, integer} when integer >= 0 -> {:ok, integer}
      _ -> {:error, "#{label} must be a non-negative integer."}
    end
  end

  defp ocf_length(value) do
    case parse_integer(value) do
      {:ok, 0} -> {:ok, 0}
      {:ok, 4} -> {:ok, 4}
      _ -> {:error, "Operational Control Field must be 0 (absent) or 4 (present)."}
    end
  end

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(true), do: {:ok, true}
  defp boolean(false), do: {:ok, false}
  defp boolean(_), do: {:error, "Truncated primary header must be Yes or No."}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_), do: :error

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_), do: nil

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  defp format_error(reason), do: "Failed to create spacecraft profile: #{inspect(reason)}"
end
