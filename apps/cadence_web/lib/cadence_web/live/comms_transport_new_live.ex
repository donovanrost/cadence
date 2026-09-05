defmodule CadenceWeb.CommsTransportNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.Transport
  alias Cadence.ExtensionCatalog
  alias Cadence.Extensions.Presentation.{ConfigurationDefinition, FieldDefinition}
  alias Cadence.Management.Providers
  alias Cadence.Management.Transports
  alias Phoenix.HTML.Form

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    providers = Providers.list_providers(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Transport")
     |> assign(:nav_item, :comms_transports)
     |> assign(:return_to, ~p"/missions/#{mission.mission_id}/comms/transports")
     |> assign(:providers, providers)
     |> assign(:transport_kind_options, transport_kind_options())
     |> assign(:form_error, nil)
     |> assign_form_state(default_form_params())}
  end

  @impl true
  def handle_event("validate", %{"transport" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form_error, nil)
     |> assign_form_state(params)}
  end

  @impl true
  def handle_event("save", %{"transport" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, transport} <-
           build_transport(params, socket.assigns.providers, mission, display_name),
         {:ok, persisted} <-
           Transports.persist_transport(scope.organization_id, transport) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission.mission_id}/comms/transports/#{persisted.transport_id}"
       )}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign_form_state(params)
         |> assign(:form_error, format_error(reason))}
    end
  rescue
    error in ArgumentError ->
      {:noreply,
       socket
       |> assign_form_state(params)
       |> assign(:form_error, error.message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-transport-new-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="transport"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp transport_page_dto(mission, return_to) do
    %{
      id: "comms-transport-new-page",
      title: "New Transport",
      subtitle:
        "Describe a durable byte-moving capability. This setup does not mean a connection is currently open.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{label: "Transports", href: return_to},
        %{label: "New Transport", href: nil}
      ]
    }
  end

  defp transport_form_dto(assigns) do
    form = assigns.form
    definition = assigns.kind_entry.configuration

    %{
      id: "transport-form",
      selected_origin: assigns.selected_origin,
      can_submit: assigns.can_submit?,
      sections: sections_dto(),
      fields: form_fields_dto(assigns, form),
      origin_cards: origin_cards_dto(),
      direct_configuration:
        configuration_dto(definition, form, assigns.selected_origin == "direct"),
      provider: provider_dto(assigns),
      provider_derived: provider_derived_dto(assigns),
      review: review_dto(assigns),
      actions: %{
        submit: %{id: "create-transport-button", label: "Create Transport"},
        cancel: %{id: "cancel-transport-link", label: "Cancel", href: assigns.return_to}
      }
    }
  end

  defp sections_dto do
    %{
      identity: %{id: "transport-identity-section", number: "01", title: "Identity"},
      origin: %{id: "transport-origin-section", number: "02", title: "Origin"},
      source: %{id: "transport-source-section", number: "03", title: "Source"},
      provider_capability: %{
        id: "transport-capability-section",
        number: "04",
        title: "Capability"
      },
      review: %{id: "transport-summary-section", number: "06", title: "Review"}
    }
  end

  defp form_fields_dto(assigns, form) do
    %{
      display_name:
        form_field_dto(:display_name, "transport-display-name", "text", "Display Name", form,
          required: true
        ),
      origin:
        form_field_dto(:origin, "transport-origin", "select", "Configuration Owner", form,
          required: true,
          options: origin_options()
        ),
      transport_kind:
        form_field_dto(:transport_kind, "transport-kind", "select", "Transport Kind", form,
          required: true,
          options: assigns.transport_kind_options,
          provider_managed_id: "transport-kind-provider-managed"
        ),
      mission_provider_id:
        form_field_dto(
          :mission_provider_id,
          "transport-provider",
          "select",
          "Ground Network Provider",
          form,
          required: true,
          placeholder: "Select a validated provider",
          options: provider_options(assigns.providers)
        ),
      service_profile_id:
        form_field_dto(
          :service_profile_id,
          "transport-service-profile",
          "select",
          "Service Profile",
          form,
          required: true,
          placeholder: "Select service",
          options: profile_options(assigns.service_profiles)
        ),
      delivery_profile_id:
        form_field_dto(
          :delivery_profile_id,
          "transport-delivery-profile",
          "select",
          "Delivery Profile",
          form,
          required: true,
          placeholder: "Select delivery",
          options: delivery_profile_options(assigns.delivery_profiles)
        )
    }
  end

  defp form_field_dto(field, id, type, label, form, opts) do
    key = Atom.to_string(field)

    %{
      key: key,
      id: id,
      name: "transport[#{key}]",
      type: type,
      label: label,
      required: Keyword.get(opts, :required, false),
      placeholder: Keyword.get(opts, :placeholder),
      options: opts |> Keyword.get(:options, []) |> Enum.map(&option_dto/1),
      value: form_value(form, field),
      provider_managed_id: Keyword.get(opts, :provider_managed_id)
    }
  end

  defp origin_cards_dto do
    [
      %{
        value: "direct",
        label: "Direct",
        description: "Cadence owns the endpoint, framing, TLS, and reconnect setup."
      },
      %{
        value: "provider_managed",
        label: "Ground Station Provider",
        description:
          "Cadence derives read-only runtime setup from synchronized provider profiles."
      }
    ]
  end

  defp configuration_dto(%ConfigurationDefinition{} = definition, form, active?) do
    %{
      id: definition.id,
      kind: "transport_kind",
      description: definition.description,
      active: active?,
      sections:
        Enum.map(
          definition.sections,
          &configuration_section_dto(&1, definition.id, form)
        )
    }
  end

  defp configuration_section_dto(section, definition_id, form) do
    %{
      id: section.id,
      fields_id: "#{section.id}-fields",
      number: section.number,
      title: section.title,
      description: section.description,
      fields: Enum.map(section.fields, &configuration_field_dto(&1, definition_id, form))
    }
  end

  defp configuration_field_dto(%FieldDefinition{} = field, definition_id, form) do
    key = Atom.to_string(field.field)
    dom_field = String.replace(key, "_", "-")

    %{
      key: key,
      wrapper_id: "#{definition_id}-field-#{dom_field}",
      id: "#{definition_id}-input-#{dom_field}",
      name: "transport[#{key}]",
      type: configuration_input_type(field.type),
      label: field.label,
      required: field.required,
      placeholder: field.placeholder,
      help: field.help,
      step: field.step,
      min: field.min,
      max: field.max,
      default: presentation_value(field.default),
      value: form_value(form, field.field),
      options: Enum.map(field.options, &option_dto/1),
      visible: field_visible?(field.visible_when, form),
      visible_when: visibility_dto(field.visible_when)
    }
  end

  defp provider_dto(assigns) do
    %{
      active: assigns.selected_origin == "provider_managed",
      profile_fields_id: "transport-provider-profile-fields",
      ready_count: assigns.provider_ready_count,
      selected: selected_provider_dto(assigns.selected_provider),
      empty_state: %{
        id: "transport-provider-empty-state",
        visible: assigns.provider_ready_count == 0,
        message: "No provider has both a healthy validation and synchronized profiles.",
        action: %{
          label: "Review providers",
          href: ~p"/missions/#{assigns.current_mission.mission_id}/comms/providers"
        }
      },
      operator_summary: operator_summary_dto(assigns.selected_delivery, assigns.derived_summary),
      derivation_error: assigns.derivation_error
    }
  end

  defp selected_provider_dto(nil), do: nil

  defp selected_provider_dto(provider) do
    %{
      display_name: provider.display_name,
      version: provider.version,
      status: "ready",
      status_label: "Profiles synced"
    }
  end

  defp operator_summary_dto(nil, _summary), do: nil

  defp operator_summary_dto(delivery, summary) do
    %{
      id: "transport-provider-operator-summary",
      label: "Operator Summary",
      text: delivery["operator_summary"],
      endpoint: summary_endpoint(summary)
    }
  end

  defp provider_derived_dto(assigns) do
    %{
      active: assigns.selected_origin == "provider_managed",
      id: "transport-provider-derived-section",
      number: "05",
      title: "Provider-Derived Runtime",
      description:
        "Endpoint, framing, and reliability are provider-owned for this Transport and remain read-only.",
      configuration: derived_configuration_dto(assigns.derived_configuration, assigns.kind_entry)
    }
  end

  defp derived_configuration_dto(nil, _kind_entry) do
    %{
      id: "transport-provider-derived-configuration",
      rows: [],
      empty_text: "Select compatible provider profiles to derive runtime configuration."
    }
  end

  defp derived_configuration_dto(configuration, kind_entry) do
    summary = kind_entry.module.display_summary(configuration)

    %{
      id: "transport-provider-derived-configuration",
      rows: [
        detail_dto("Actual kind", kind_entry.label),
        detail_dto("Mode", human_text(summary.mode)),
        detail_dto("Direction", human_text(summary.direction_capability)),
        detail_dto("Endpoint", summary.endpoint, true),
        detail_dto("Framing", human_text(summary.framing)),
        detail_dto("TLS", if(summary.tls_enabled?, do: "Enabled", else: "Disabled"))
      ],
      empty_text: nil
    }
  end

  defp detail_dto(label, value, mono? \\ false),
    do: %{label: label, value: value, mono: mono?}

  defp review_dto(assigns) do
    %{
      configuration_summary_id: "transport-configuration-summary",
      ownership: %{
        label: "Ownership",
        value: origin_label(assigns.selected_origin),
        source: source_summary(assigns.selected_origin, assigns.selected_provider)
      },
      readiness: %{
        label: "Readiness",
        status: if(assigns.can_submit?, do: "ready", else: "attention"),
        value: if(assigns.can_submit?, do: "Ready to save", else: "Incomplete"),
        endpoint: summary_endpoint(assigns.derived_summary)
      },
      error: assigns.form_error,
      error_id: "transport-form-error",
      diagnostics: %{
        id: "transport-admin-diagnostics",
        label: "Administrator Diagnostics",
        json_id: "transport-admin-diagnostics-json",
        json: diagnostics_json(assigns)
      }
    }
  end

  defp option_dto({label, value}),
    do: %{label: label, value: presentation_value(value), disabled: false}

  defp option_dto({label, value, opts}) do
    %{
      label: label,
      value: presentation_value(value),
      disabled: Keyword.get(opts, :disabled, false)
    }
  end

  defp visibility_dto(nil), do: nil

  defp visibility_dto(%{field: field, equals: expected}) do
    %{field: Atom.to_string(field), equals: presentation_value(expected)}
  end

  defp field_visible?(nil, _form), do: true

  defp field_visible?(%{field: field, equals: expected}, form),
    do: form_value(form, field) == presentation_value(expected)

  defp configuration_input_type(:reference), do: "select"
  defp configuration_input_type(type), do: Atom.to_string(type)

  defp form_value(form, field), do: form |> Form.input_value(field) |> presentation_value()

  defp presentation_value(nil), do: ""
  defp presentation_value(value) when is_binary(value), do: value
  defp presentation_value(value) when is_boolean(value), do: to_string(value)
  defp presentation_value(value) when is_atom(value), do: Atom.to_string(value)
  defp presentation_value(value) when is_number(value), do: to_string(value)
  defp presentation_value(value), do: inspect(value)

  defp assign_form_state(socket, raw_params) do
    params = normalize_form_params(raw_params)
    selected_origin = params["origin"]
    {:ok, kind_entry} = ExtensionCatalog.fetch_transport_kind(params["transport_kind"])

    {params, selected_provider, service_profiles, selected_service, delivery_profiles,
     selected_delivery} =
      provider_form_state(params, socket.assigns.providers, kind_entry)

    {derived_configuration, derived_summary, derivation_error} =
      derive_configuration(selected_origin, params, selected_delivery, kind_entry)

    can_submit? =
      is_binary(normalize_text(params["display_name"])) and is_map(derived_configuration) and
        (selected_origin == "direct" or
           (not is_nil(selected_provider) and not is_nil(selected_service) and
              not is_nil(selected_delivery)))

    socket
    |> assign(:selected_origin, selected_origin)
    |> assign(:kind_entry, kind_entry)
    |> assign(:selected_provider, selected_provider)
    |> assign(:service_profiles, service_profiles)
    |> assign(:selected_service, selected_service)
    |> assign(:delivery_profiles, delivery_profiles)
    |> assign(:selected_delivery, selected_delivery)
    |> assign(:derived_configuration, derived_configuration)
    |> assign(:derived_summary, derived_summary)
    |> assign(:derivation_error, derivation_error)
    |> assign(:provider_ready_count, Enum.count(socket.assigns.providers, &provider_ready?/1))
    |> assign(:can_submit?, can_submit?)
    |> assign(:form, to_form(params, as: :transport))
  end

  defp normalize_form_params(params) do
    transport_kind =
      case ExtensionCatalog.fetch_transport_kind(params["transport_kind"] || "tcp_socket") do
        {:ok, entry} -> entry.form_value
        {:error, _reason} -> "tcp_socket"
      end

    params
    |> Map.put_new("origin", "direct")
    |> Map.update("origin", "direct", fn
      origin when origin in ["direct", "provider_managed"] -> origin
      _other -> "direct"
    end)
    |> Map.put("transport_kind", transport_kind)
  end

  defp provider_form_state(
         %{"origin" => "provider_managed"} = params,
         providers,
         kind_entry
       ) do
    selected_provider =
      select_provider(providers, params["mission_provider_id"]) ||
        Enum.find(providers, &provider_ready?/1)

    service_profiles =
      selected_provider
      |> profile_items("service_profiles")
      |> Enum.filter(&(&1["state"] == "active" and &1["direction"] == "downlink"))

    selected_service = select_profile(service_profiles, params["service_profile_id"])
    selected_service = selected_service || List.first(service_profiles)

    delivery_profiles = compatible_deliveries(selected_provider, selected_service, kind_entry)
    selected_delivery = select_profile(delivery_profiles, params["delivery_profile_id"])
    selected_delivery = selected_delivery || List.first(delivery_profiles)

    params =
      params
      |> put_selected("mission_provider_id", selected_provider)
      |> put_selected("service_profile_id", selected_service)
      |> put_selected("delivery_profile_id", selected_delivery)

    {params, selected_provider, service_profiles, selected_service, delivery_profiles,
     selected_delivery}
  end

  defp provider_form_state(params, _providers, _kind_entry),
    do: {params, nil, [], nil, [], nil}

  defp derive_configuration("provider_managed", _params, delivery_profile, kind_entry) do
    case kind_entry.module.from_delivery_profile(delivery_profile) do
      {:ok, configuration} ->
        {configuration, kind_entry.module.display_summary(configuration), nil}

      {:error, message} ->
        {nil, nil, message}
    end
  end

  defp derive_configuration("direct", params, _delivery_profile, kind_entry) do
    case kind_entry.module.normalize_config(direct_config_params(params)) do
      {:ok, configuration} ->
        {configuration, kind_entry.module.display_summary(configuration), nil}

      {:error, message} ->
        {nil, nil, message}
    end
  end

  defp build_transport(%{"origin" => "direct"} = params, _providers, mission, display_name) do
    with {:ok, entry} <- ExtensionCatalog.fetch_transport_kind(params["transport_kind"]),
         {:ok, configuration} <- entry.module.normalize_config(direct_config_params(params)) do
      {:ok,
       Transport.new(%{
         mission_id: mission.mission_id,
         display_name: display_name,
         origin: :direct,
         transport_kind: entry.kind,
         adapter_key: entry.adapter_key,
         direction_capability: configuration["direction_capability"],
         configuration: configuration
       })}
    end
  end

  defp build_transport(
         %{"origin" => "provider_managed"} = params,
         providers,
         mission,
         display_name
       ) do
    with {:ok, entry} <- ExtensionCatalog.fetch_transport_kind(params["transport_kind"]),
         %{} = provider <- select_provider(providers, params["mission_provider_id"]),
         true <- provider_ready?(provider),
         service_profiles <- profile_items(provider, "service_profiles"),
         %{} = service_profile <- select_profile(service_profiles, params["service_profile_id"]),
         delivery_profiles <- compatible_deliveries(provider, service_profile, entry),
         %{} = delivery_profile <-
           select_profile(delivery_profiles, params["delivery_profile_id"]),
         {:ok, configuration} <- entry.module.from_delivery_profile(delivery_profile) do
      {:ok,
       Transport.new(%{
         mission_id: mission.mission_id,
         display_name: display_name,
         origin: :provider_managed,
         transport_kind: entry.kind,
         adapter_key: entry.adapter_key,
         direction_capability: configuration["direction_capability"],
         configuration: configuration,
         mission_provider_id: provider.provider_id,
         mission_provider_version: provider.version,
         service_profile_ref: profile_ref(service_profile),
         delivery_profile_ref: profile_ref(delivery_profile)
       })}
    else
      nil -> {:error, :provider_managed_transport_selection_incomplete}
      false -> {:error, :mission_provider_not_validated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_transport(_params, _providers, _mission, _display_name),
    do: {:error, :invalid_transport_origin}

  defp compatible_deliveries(nil, _service, _kind_entry), do: []
  defp compatible_deliveries(_provider, nil, _kind_entry), do: []

  defp compatible_deliveries(provider, service, kind_entry) do
    provider
    |> profile_items("delivery_profiles")
    |> Enum.filter(fn delivery ->
      delivery["state"] == "ready" and delivery["direction"] == "downlink" and
        service["id"] in (delivery["supported_service_profile_refs"] || []) and
        match?({:ok, _configuration}, kind_entry.module.from_delivery_profile(delivery))
    end)
  end

  defp profile_items(nil, _key), do: []

  defp profile_items(provider, key) do
    case get_in(provider.inventory_sync_document, [key, "items"]) do
      items when is_list(items) -> items
      _other -> []
    end
  end

  defp select_provider(providers, provider_id) do
    Enum.find(providers, &(&1.provider_id == provider_id and provider_ready?(&1)))
  end

  defp select_profile(profiles, token) do
    with {:ok, encoded} when is_binary(encoded) <- Base.url_decode64(token || "", padding: false),
         {:ok, %{"id" => id, "version" => version}} <- Jason.decode(encoded) do
      Enum.find(profiles, &(&1["id"] == id and &1["version"] == version))
    else
      _other -> nil
    end
  end

  defp provider_ready?(provider) do
    match?(%DateTime{}, provider.last_validated_at) and
      match?(%DateTime{}, provider.last_synced_at) and
      get_in(provider.metadata, ["control_plane", "status"]) == "healthy"
  end

  defp put_selected(params, key, nil), do: Map.put(params, key, "")

  defp put_selected(params, "mission_provider_id", provider),
    do: Map.put(params, "mission_provider_id", provider.provider_id)

  defp put_selected(params, key, profile), do: Map.put(params, key, profile_token(profile))

  defp profile_ref(profile), do: %{"id" => profile["id"], "version" => profile["version"]}

  defp direct_config_params(params) do
    %{
      "mode" => params["tcp_mode"],
      "direction_capability" => params["direction_capability"],
      "host" => params["host"],
      "port" => params["port"],
      "framing_mode" => params["framing_mode"],
      "frame_size" => params["frame_size"],
      "reconnect_policy" => params["reconnect_policy"],
      "tls_enabled" => params["tls_enabled"]
    }
  end

  defp default_form_params do
    {:ok, definition} = ExtensionCatalog.fetch_transport_kind("tcp_socket")

    Map.merge(
      %{
        "display_name" => "",
        "origin" => "direct",
        "transport_kind" => definition.form_value
      },
      ConfigurationDefinition.default_params(definition.configuration)
    )
  end

  defp transport_kind_options do
    ExtensionCatalog.transport_kinds()
    |> Enum.map(&{&1.label, &1.form_value})
    |> Enum.sort()
  end

  defp provider_options(providers) do
    Enum.map(providers, fn provider ->
      label = "#{provider.display_name} · v#{provider.version}"
      {label, provider.provider_id, disabled: not provider_ready?(provider)}
    end)
  end

  defp profile_options(profiles),
    do:
      Enum.map(
        profiles,
        &{"#{&1["display_name"]} · v#{&1["version"]}", profile_token(&1)}
      )

  defp delivery_profile_options(profiles) do
    Enum.map(profiles, fn profile ->
      {profile["operator_summary"] || profile["display_name"], profile_token(profile)}
    end)
  end

  defp profile_token(profile) do
    profile
    |> Map.take(["id", "version"])
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp origin_options,
    do: [
      {"Direct — configured in Cadence", "direct"},
      {"Ground Station Provider", "provider_managed"}
    ]

  defp origin_label("provider_managed"), do: "Ground Station Provider"
  defp origin_label(_origin), do: "Direct"

  defp source_summary("provider_managed", provider) when is_map(provider),
    do: "#{provider.display_name} · v#{provider.version}"

  defp source_summary("provider_managed", _provider), do: "Select a validated provider"
  defp source_summary(_origin, _provider), do: "Cadence-managed TCP socket"

  defp summary_endpoint(nil), do: "Endpoint not yet resolved"
  defp summary_endpoint(summary), do: summary.endpoint

  defp diagnostics_json(assigns) do
    Jason.encode!(
      %{
        "origin" => assigns.selected_origin,
        "provider" => diagnostics_provider(assigns.selected_provider),
        "service_profile" => assigns.selected_service,
        "delivery_profile" => assigns.selected_delivery,
        "derived_configuration" => assigns.derived_configuration
      },
      pretty: true
    )
  end

  defp diagnostics_provider(nil), do: nil

  defp diagnostics_provider(provider) do
    %{
      "id" => provider.provider_id,
      "version" => provider.version,
      "display_name" => provider.display_name,
      "environment_ref" => provider.environment_ref
    }
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

  defp human_text(value) when is_binary(value),
    do: value |> String.replace("_", " ") |> String.upcase()

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

  defp format_error(:unsupported_transport_kind), do: "Select a supported Transport kind."

  defp format_error(:mission_provider_not_validated),
    do: "Validate and sync the selected provider first."

  defp format_error(:provider_managed_transport_selection_incomplete),
    do: "Select a compatible provider, Service Profile, and Delivery Profile."

  defp format_error(message) when is_binary(message), do: message
  defp format_error(reason), do: "Failed to create transport: #{inspect(reason)}"
end
