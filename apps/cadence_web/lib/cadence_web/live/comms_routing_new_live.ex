defmodule CadenceWeb.CommsRoutingNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  alias Cadence.Comms.RoutingRule

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    spacecraft =
      Cadence.SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)

    transports =
      TransportStore.list_transports(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Routing Rule")
     |> assign(:nav_item, :comms_routing)
     |> assign(:page, page_dto(mission))
     |> assign(:form, form_dto(empty_form_params(params), mission))
     |> assign(:options, options_dto(spacecraft, transports))}
  end

  @impl true
  def handle_event("validate", %{"routing_rule" => params}, socket) do
    {:noreply, assign(socket, :form, form_dto(params, socket.assigns.current_mission))}
  end

  @impl true
  def handle_event("save", %{"routing_rule" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, purpose_label} <- required_text(params["purpose_label"], "Purpose is required."),
         {:ok, spacecraft_id} <- required_text(params["spacecraft_id"], "Spacecraft is required."),
         {:ok, transport_ref} <- transport_ref(params["transport_ref"]),
         {:ok, direction} <-
           known_value(
             params["direction"],
             ["inbound", "outbound", "bidirectional"],
             "Direction is invalid."
           ),
         {:ok, role} <-
           known_value(
             params["role"],
             ["primary", "candidate", "contributing"],
             "Role is invalid."
           ) do
      routing_rule =
        RoutingRule.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: spacecraft_id,
          display_name: display_name,
          purpose_label: purpose_label,
          direction: direction,
          transport_id: transport_ref.transport_id,
          transport_version: transport_ref.version,
          role: role,
          enabled?: true
        })

      case RoutingRuleStore.create_routing_rule(scope.organization_id, routing_rule) do
        {:ok, persisted} ->
          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/comms/routing/#{persisted.routing_rule_id}"
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-routing-new-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="routing_new"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
        class="space-y-6 max-w-2xl"
      />
    </Layouts.app>
    """
  end

  defp empty_form_params(params) do
    %{
      "display_name" => "",
      "purpose_label" => "Live telemetry",
      "spacecraft_id" => Map.get(params, "spacecraft_id", ""),
      "transport_ref" => "",
      "direction" => "inbound",
      "role" => "primary"
    }
  end

  defp page_dto(mission) do
    %{
      id: "comms-routing-new-page",
      title: "New Routing Rule",
      subtitle:
        "Declare durable spacecraft use of a transport for a purpose and direction. Contacts and runtime Links are handled later.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{label: "Routing", href: ~p"/missions/#{mission.mission_id}/comms/routing"},
        %{label: "New Routing Rule", href: nil}
      ]
    }
  end

  defp form_dto(params, mission) do
    %{
      id: "routing-rule-form",
      sections: %{
        intent: %{number: "01", title: "Intent"},
        transport: %{number: "02", title: "Spacecraft And Transport"},
        policy: %{number: "03", title: "Routing Policy"}
      },
      fields: %{
        display_name:
          field_dto(
            :display_name,
            "text",
            "Display Name",
            string_param(params, "display_name")
          ),
        purpose_label:
          field_dto(:purpose_label, "text", "Purpose", string_param(params, "purpose_label")),
        spacecraft_id:
          field_dto(
            :spacecraft_id,
            "select",
            "Spacecraft",
            string_param(params, "spacecraft_id")
          ),
        transport_ref:
          field_dto(
            :transport_ref,
            "select",
            "Transport",
            string_param(params, "transport_ref")
          ),
        direction:
          field_dto(:direction, "select", "Direction", string_param(params, "direction")),
        role: field_dto(:role, "select", "Role", string_param(params, "role"))
      },
      actions: %{
        submit: %{id: "create-routing-rule-button", label: "Create Routing Rule"},
        cancel: %{
          id: "cancel-routing-rule-link",
          label: "Cancel",
          href: ~p"/missions/#{mission.mission_id}/comms/routing"
        }
      }
    }
  end

  defp field_dto(field, type, label, value) do
    field_name = Atom.to_string(field)

    %{
      id: "routing_rule_#{field_name}",
      name: "routing_rule[#{field_name}]",
      type: type,
      label: label,
      required: true,
      value: value
    }
  end

  defp options_dto(spacecraft, transports) do
    %{
      spacecraft: [
        option_dto("Select spacecraft", "")
        | Enum.map(spacecraft, &option_dto(&1.display_name, &1.spacecraft_id))
      ],
      transports: [
        option_dto("Select transport", "")
        | Enum.map(
            transports,
            &option_dto(
              "#{&1.display_name} (v#{&1.version})",
              "#{&1.transport_id}:#{&1.version}"
            )
          )
      ],
      directions: [
        option_dto("Inbound", "inbound"),
        option_dto("Outbound", "outbound"),
        option_dto("Bidirectional", "bidirectional")
      ],
      roles: [
        option_dto("Primary", "primary"),
        option_dto("Candidate", "candidate"),
        option_dto("Contributing", "contributing")
      ]
    }
  end

  defp option_dto(label, value), do: %{label: label, value: value}

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp transport_ref(value) do
    case String.split(to_string(value || ""), ":", parts: 2) do
      [transport_id, version] when transport_id != "" ->
        case Integer.parse(version) do
          {version, ""} when version > 0 -> {:ok, %{transport_id: transport_id, version: version}}
          _other -> {:error, "Transport is invalid."}
        end

      _other ->
        {:error, "Transport is required."}
    end
  end

  defp known_value(value, allowed, message) do
    if value in allowed do
      {:ok, value}
    else
      {:error, message}
    end
  end

  defp required_text(value, message) do
    case normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil

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

  defp format_error(reason), do: "Failed to create routing rule: #{inspect(reason)}"
end
