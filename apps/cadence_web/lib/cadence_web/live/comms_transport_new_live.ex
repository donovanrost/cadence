defmodule CadenceWeb.CommsTransportNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.{Transport, TransportKind}
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.GroundNetworks
  alias Phoenix.HTML.Form

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    providers = GroundNetworks.list_providers(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Transport")
     |> assign(:nav_item, :comms_transports)
     |> assign(:return_to, ~p"/missions/#{mission.mission_id}/comms/transports")
     |> assign(:providers, providers)
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
           TransportStore.persist_transport(scope.organization_id, transport) do
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
    <div id="comms-transport-new-page" class="mx-auto max-w-4xl space-y-6">
      <.page_header
        title="New Transport"
        subtitle="Describe a durable byte-moving capability. This setup does not mean a connection is currently open."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Transports", @return_to},
          {"New Transport", nil}
        ]}
      />

      <.form
        for={@form}
        id="transport-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <.form_section id="transport-identity-section" number="01" title="Identity">
          <.input
            id="transport-display-name"
            field={@form[:display_name]}
            type="text"
            label="Display Name"
            required
          />
        </.form_section>

        <.form_section id="transport-origin-section" number="02" title="Origin">
          <.input
            id="transport-origin"
            field={@form[:origin]}
            type="select"
            label="Configuration Owner"
            options={origin_options()}
            required
          />
          <div class="grid gap-3 md:grid-cols-2">
            <div class={origin_card_class(@selected_origin == "direct")}>
              <p class="hud-label">Direct</p>
              <p class="mt-2 text-sm text-base-content/65">
                Cadence owns the endpoint, framing, TLS, and reconnect setup.
              </p>
            </div>
            <div class={origin_card_class(@selected_origin == "provider_managed")}>
              <p class="hud-label">Ground Station Provider</p>
              <p class="mt-2 text-sm text-base-content/65">
                Cadence derives read-only runtime setup from synchronized provider profiles.
              </p>
            </div>
          </div>
        </.form_section>

        <.form_section id="transport-source-section" number="03" title="Source">
          <%= if @selected_origin == "direct" do %>
            <.input
              id="transport-kind"
              field={@form[:transport_kind]}
              type="select"
              label="Transport Kind"
              options={TransportKind.form_options()}
              required
            />
          <% else %>
            <.input
              id="transport-provider"
              field={@form[:mission_provider_id]}
              type="select"
              label="Ground Network Provider"
              options={provider_options(@providers)}
              placeholder="Select a validated provider"
              required
            />
            <div
              :if={@provider_ready_count == 0}
              id="transport-provider-empty-state"
              class="border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70"
            >
              No provider has both a healthy validation and synchronized profiles.
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
                class="ml-1 text-primary hover:underline"
              >
                Review providers
              </.link>
            </div>
          <% end %>
        </.form_section>

        <.form_section id="transport-capability-section" number="04" title="Capability">
          <%= if @selected_origin == "direct" do %>
            <.direct_endpoint_fields form={@form} kind_entry={@kind_entry} />
          <% else %>
            <.provider_profile_fields
              form={@form}
              selected_provider={@selected_provider}
              service_profiles={@service_profiles}
              delivery_profiles={@delivery_profiles}
              selected_delivery={@selected_delivery}
              derived_summary={@derived_summary}
              derivation_error={@derivation_error}
            />
          <% end %>
        </.form_section>

        <%= if @selected_origin == "direct" do %>
          <.direct_configuration_fields form={@form} kind_entry={@kind_entry} />
        <% else %>
          <section id="transport-provider-derived-section" class="space-y-4">
            <div class="flex items-center gap-3">
              <span class="hud-label text-primary/70">05</span>
              <h2 class="hud-label">Provider-Derived Runtime</h2>
              <div class="h-px flex-1 bg-base-300/60"></div>
            </div>
            <p class="text-sm text-base-content/65">
              Endpoint, framing, and reliability are provider-owned for this Transport and remain read-only.
            </p>
            <.derived_configuration configuration={@derived_configuration} />
          </section>
        <% end %>

        <section id="transport-summary-section" class="space-y-4">
          <div class="flex items-center gap-3">
            <span class="hud-label text-primary/70">06</span>
            <h2 class="hud-label">Review</h2>
            <div class="h-px flex-1 bg-base-300/60"></div>
          </div>

          <.card id="transport-configuration-summary" padding={:none}>
            <div class="grid divide-y divide-base-300 md:grid-cols-2 md:divide-x md:divide-y-0">
              <div class="p-5">
                <p class="hud-label">Ownership</p>
                <p class="mt-2 text-base font-semibold">{origin_label(@selected_origin)}</p>
                <p class="mt-1 text-sm text-base-content/60">
                  {source_summary(@selected_origin, @selected_provider)}
                </p>
              </div>
              <div class="p-5">
                <p class="hud-label">Readiness</p>
                <div class="mt-2">
                  <.status_badge
                    status={if(@can_submit?, do: :ready, else: :attention)}
                    label={if(@can_submit?, do: "Ready to save", else: "Incomplete")}
                  />
                </div>
                <p class="mt-2 font-mono text-xs text-base-content/60">
                  {summary_endpoint(@derived_summary)}
                </p>
              </div>
            </div>
          </.card>

          <p
            :if={@form_error}
            id="transport-form-error"
            class="border-l-2 border-error/70 bg-error/10 px-4 py-3 text-sm text-error"
          >
            {@form_error}
          </p>

          <details
            id="transport-admin-diagnostics"
            class="rounded border border-base-300 bg-base-100/40 p-4 text-sm"
          >
            <summary class="cursor-pointer hud-label hover:text-primary">
              Administrator Diagnostics
            </summary>
            <pre id="transport-admin-diagnostics-json" class="mt-3 max-h-96 overflow-auto font-mono text-xs text-base-content/70">{diagnostics_json(assigns)}</pre>
          </details>
        </section>

        <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
          <.button
            id="create-transport-button"
            type="submit"
            size={:md}
            disabled={!@can_submit?}
          >
            Create Transport
          </.button>
          <.button id="cancel-transport-link" variant={:ghost} size={:md} navigate={@return_to}>
            Cancel
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  attr :form, Form, required: true
  attr :kind_entry, :map, required: true

  defp direct_endpoint_fields(assigns) do
    ~H"""
    <div id="transport-direct-endpoint-fields" class="space-y-4">
      <.input
        id="transport-tcp-mode"
        field={@form[:tcp_mode]}
        type="select"
        label="TCP Mode"
        options={@kind_entry.form.modes}
        required
      />
      <.input
        id="transport-direction-capability"
        field={@form[:direction_capability]}
        type="select"
        label="Direction Capability"
        options={@kind_entry.form.directions}
        required
      />
      <.input
        id="transport-host"
        field={@form[:host]}
        type="text"
        label={host_label(@form)}
        required
      />
      <.input
        id="transport-port"
        field={@form[:port]}
        type="number"
        label={port_label(@form)}
        required
      />
    </div>
    """
  end

  attr :form, Form, required: true
  attr :selected_provider, :map, default: nil
  attr :service_profiles, :list, required: true
  attr :delivery_profiles, :list, required: true
  attr :selected_delivery, :map, default: nil
  attr :derived_summary, :map, default: nil
  attr :derivation_error, :string, default: nil

  defp provider_profile_fields(assigns) do
    ~H"""
    <div id="transport-provider-profile-fields" class="space-y-4">
      <div
        :if={@selected_provider}
        class="flex items-center justify-between border-l-2 border-success/60 bg-success/10 px-4 py-3"
      >
        <div>
          <p class="hud-label">Validated Provider</p>
          <p class="mt-1 text-sm">{@selected_provider.display_name} · v{@selected_provider.version}</p>
        </div>
        <.status_badge status={:ready} label="Profiles synced" />
      </div>
      <.input
        id="transport-service-profile"
        field={@form[:service_profile_id]}
        type="select"
        label="Service Profile"
        options={profile_options(@service_profiles)}
        placeholder="Select service"
        required
      />
      <.input
        id="transport-delivery-profile"
        field={@form[:delivery_profile_id]}
        type="select"
        label="Delivery Profile"
        options={delivery_profile_options(@delivery_profiles)}
        placeholder="Select delivery"
        required
      />
      <div
        :if={@selected_delivery}
        id="transport-provider-operator-summary"
        class="border border-base-300 bg-base-200/70 p-4"
      >
        <p class="hud-label">Operator Summary</p>
        <p class="mt-2 text-sm font-medium">{@selected_delivery["operator_summary"]}</p>
        <p class="mt-2 font-mono text-xs text-base-content/60">
          {summary_endpoint(@derived_summary)}
        </p>
      </div>
      <div
        :if={@derivation_error}
        id="transport-provider-derivation-error"
        class="border-l-2 border-warning/60 bg-warning/10 px-4 py-3 text-sm text-base-content/70"
      >
        {@derivation_error}
      </div>
    </div>
    """
  end

  attr :form, Form, required: true
  attr :kind_entry, :map, required: true

  defp direct_configuration_fields(assigns) do
    ~H"""
    <div id="transport-direct-configuration" class="space-y-8">
      <.form_section id="transport-framing-section" number="05" title="Framing">
        <.input
          id="transport-framing-mode"
          field={@form[:framing_mode]}
          type="select"
          label="Framing"
          options={@kind_entry.form.framing_modes}
          required
        />
        <.input
          :if={Form.input_value(@form, :framing_mode) == "fixed_size"}
          id="transport-frame-size"
          field={@form[:frame_size]}
          type="number"
          label="Fixed Frame Size (bytes)"
          required
        />
      </.form_section>

      <.form_section id="transport-reliability-section" number="05B" title="Reliability">
        <.input
          :if={Form.input_value(@form, :tcp_mode) == "connect"}
          id="transport-reconnect-policy"
          field={@form[:reconnect_policy]}
          type="select"
          label="Reconnect Policy"
          options={@kind_entry.form.reconnect_policies}
          required
        />
        <.input
          id="transport-tls-enabled"
          field={@form[:tls_enabled]}
          type="select"
          label="TLS"
          options={@kind_entry.form.tls_options}
          required
        />
      </.form_section>
    </div>
    """
  end

  attr :configuration, :map, default: nil

  defp derived_configuration(assigns) do
    summary =
      if assigns.configuration,
        do: TCPSocket.display_summary(assigns.configuration),
        else: nil

    assigns = assign(assigns, :summary, summary)

    ~H"""
    <.card id="transport-provider-derived-configuration">
      <div :if={@summary} class="divide-y divide-base-300">
        <.detail_row label="Actual kind" value="TCP SOCKET" />
        <.detail_row label="Mode" value={human_text(@summary.mode)} />
        <.detail_row label="Direction" value={human_text(@summary.direction_capability)} />
        <.detail_row label="Endpoint" value={@summary.endpoint} mono />
        <.detail_row label="Framing" value={human_text(@summary.framing)} />
        <.detail_row label="TLS" value={if(@summary.tls_enabled?, do: "Enabled", else: "Disabled")} />
      </div>
      <p :if={!@summary} class="text-sm text-base-content/60">
        Select compatible provider profiles to derive runtime configuration.
      </p>
    </.card>
    """
  end

  defp assign_form_state(socket, raw_params) do
    params = normalize_form_params(raw_params)
    selected_origin = params["origin"]
    {:ok, kind_entry} = TransportKind.resolve_form_value(params["transport_kind"])

    {params, selected_provider, service_profiles, selected_service, delivery_profiles,
     selected_delivery} =
      provider_form_state(params, socket.assigns.providers)

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
      case TransportKind.resolve_form_value(params["transport_kind"] || "tcp_socket") do
        {:ok, entry} -> entry.form.form_value
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

  defp provider_form_state(%{"origin" => "provider_managed"} = params, providers) do
    selected_provider =
      select_provider(providers, params["mission_provider_id"]) ||
        Enum.find(providers, &provider_ready?/1)

    service_profiles =
      selected_provider
      |> profile_items("service_profiles")
      |> Enum.filter(&(&1["state"] == "active" and &1["direction"] == "downlink"))

    selected_service = select_profile(service_profiles, params["service_profile_id"])
    selected_service = selected_service || List.first(service_profiles)

    delivery_profiles = compatible_deliveries(selected_provider, selected_service)
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

  defp provider_form_state(params, _providers), do: {params, nil, [], nil, [], nil}

  defp derive_configuration("provider_managed", _params, delivery_profile, _kind_entry) do
    case TCPSocket.from_delivery_profile(delivery_profile) do
      {:ok, configuration} ->
        {configuration, TCPSocket.display_summary(configuration), nil}

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
    with {:ok, entry} <- TransportKind.resolve_form_value(params["transport_kind"]),
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
    with %{} = provider <- select_provider(providers, params["mission_provider_id"]),
         true <- provider_ready?(provider),
         service_profiles <- profile_items(provider, "service_profiles"),
         %{} = service_profile <- select_profile(service_profiles, params["service_profile_id"]),
         delivery_profiles <- compatible_deliveries(provider, service_profile),
         %{} = delivery_profile <-
           select_profile(delivery_profiles, params["delivery_profile_id"]),
         {:ok, configuration} <- TCPSocket.from_delivery_profile(delivery_profile) do
      {:ok,
       Transport.new(%{
         mission_id: mission.mission_id,
         display_name: display_name,
         origin: :provider_managed,
         transport_kind: :tcp_socket,
         adapter_key: :tcp_socket,
         direction_capability: :inbound,
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

  defp compatible_deliveries(nil, _service), do: []
  defp compatible_deliveries(_provider, nil), do: []

  defp compatible_deliveries(provider, service) do
    provider
    |> profile_items("delivery_profiles")
    |> Enum.filter(fn delivery ->
      delivery["state"] == "ready" and delivery["direction"] == "downlink" and
        service["id"] in (delivery["supported_service_profile_refs"] || []) and
        match?({:ok, _configuration}, TCPSocket.from_delivery_profile(delivery))
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
    %{
      "display_name" => "",
      "origin" => "direct",
      "transport_kind" => "tcp_socket",
      "tcp_mode" => "listen",
      "direction_capability" => "inbound",
      "host" => "0.0.0.0",
      "port" => "",
      "framing_mode" => "raw",
      "frame_size" => "",
      "reconnect_policy" => "always",
      "tls_enabled" => "false"
    }
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

  defp origin_card_class(selected?) do
    [
      "border bg-base-200 p-4 transition-colors",
      if(selected?, do: "border-primary/60", else: "border-base-300")
    ]
  end

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

  defp host_label(form) do
    if Form.input_value(form, :tcp_mode) == "connect",
      do: "Remote Host",
      else: "Bind Host / Interface"
  end

  defp port_label(form) do
    if Form.input_value(form, :tcp_mode) == "connect",
      do: "Remote Port",
      else: "Listen Port"
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
