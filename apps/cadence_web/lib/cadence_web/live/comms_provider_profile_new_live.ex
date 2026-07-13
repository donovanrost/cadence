defmodule CadenceWeb.CommsProviderProfileNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias Cadence.Contacts.ProviderProfile
  alias Phoenix.HTML.Form

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_form_state(socket, params)}
  end

  @impl true
  def handle_event("validate", %{"provider_profile" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :provider_profile))}
  end

  @impl true
  def handle_event("save", %{"provider_profile" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    display_name = normalize_text(params["display_name"])

    with true <- not is_nil(display_name),
         {:ok, configuration} <- tcp_configuration(params) do
      case save_provider_profile(
             socket,
             scope.organization_id,
             mission,
             display_name,
             configuration
           ) do
        {:ok, _provider_profile} ->
          {:noreply,
           push_navigate(socket,
             to: provider_profile_return_path(socket, mission.mission_id)
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, format_error(reason))}
      end
    else
      false ->
        {:noreply, put_flash(socket, :error, "Display name is required.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-provider-profile-new-page" class="space-y-6 max-w-2xl">
      <.page_header
        title={@heading}
        subtitle="Configure a reusable transport adapter. Spacecraft-specific byte interpretation lives on the spacecraft's type."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Providers", @return_to},
          {@heading, nil}
        ]}
      />

      <.form
        for={@form}
        id="provider-profile-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <.identity_section form={@form} />
        <.connection_section form={@form} />
        <.framing_section form={@form} />
        <.reliability_section form={@form} />
        <.scheduling_section form={@form} />

        <details class="rounded border border-base-300 bg-base-100/40 p-4 text-sm">
          <summary class="cursor-pointer hud-label hover:text-primary">
            Configuration Preview
          </summary>
          <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(preview_configuration(@form), pretty: true)}</pre>
        </details>

        <.form_actions submit={@submit_label} cancel_navigate={@return_to} />
      </.form>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp identity_section(assigns) do
    ~H"""
    <.form_section number="01" title="Identity">
      <.input field={@form[:display_name]} type="text" label="Display Name" required />
    </.form_section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp connection_section(assigns) do
    ~H"""
    <.form_section number="02" title="Connection">
      <.input
        field={@form[:tcp_mode]}
        type="select"
        label="TCP Mode"
        options={tcp_mode_options()}
        required
      />
      <.input
        field={@form[:direction]}
        type="select"
        label="Direction"
        options={tcp_direction_options()}
        required
      />
      <.input field={@form[:host]} type="text" label={host_label(@form)} required />
      <.input field={@form[:port]} type="number" label={port_label(@form)} required />
    </.form_section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp framing_section(assigns) do
    ~H"""
    <.form_section number="03" title="Framing">
      <.input
        field={@form[:framing_mode]}
        type="select"
        label="Framing"
        options={framing_options()}
        required
      />
      <.input
        field={@form[:frame_size]}
        type="number"
        label="Fixed Frame Size (bytes, only for fixed-size framing)"
      />
    </.form_section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp reliability_section(assigns) do
    ~H"""
    <.form_section number="04" title="Reliability">
      <.input
        field={@form[:reconnect_policy]}
        type="select"
        label="Reconnect Policy"
        options={reconnect_policy_options()}
        required
      />
      <.input
        field={@form[:tls_enabled]}
        type="select"
        label="TLS"
        options={tls_options()}
        required
      />
    </.form_section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp scheduling_section(assigns) do
    ~H"""
    <.form_section number="05" title="Contact Scheduling API">
      <p class="text-sm text-base-content/60">
        Optional provider control plane for discovering, reserving, and canceling contacts.
      </p>
      <.input
        field={@form[:scheduling_enabled]}
        type="select"
        label="External Scheduling"
        options={enabled_options()}
        required
      />
      <.input
        field={@form[:scheduling_client]}
        type="select"
        label="Provider Integration"
        options={scheduling_client_options()}
      />
      <.input field={@form[:scheduling_base_url]} type="url" label="Provider API URL" />
      <.input field={@form[:scheduling_api_token]} type="password" label="Provider API Token" />
      <.input
        field={@form[:scheduling_delivery_host]}
        type="text"
        label="Cadence Telemetry Delivery Host"
      />
      <.input
        field={@form[:scheduling_run_id]}
        type="text"
        label="Provider Environment / Run ID"
      />
    </.form_section>
    """
  end

  defp empty_form do
    to_form(
      empty_form_params(),
      as: :provider_profile
    )
  end

  defp empty_form_params do
    %{
      "display_name" => "",
      "tcp_mode" => "listen",
      "direction" => "downlink",
      "host" => "0.0.0.0",
      "port" => "",
      "framing_mode" => "raw",
      "frame_size" => "",
      "reconnect_policy" => "none",
      "tls_enabled" => "false",
      "scheduling_enabled" => "false",
      "scheduling_client" => "simulator_http",
      "scheduling_base_url" => "",
      "scheduling_api_token" => "",
      "scheduling_delivery_host" => "127.0.0.1",
      "scheduling_run_id" => ""
    }
  end

  defp form_from_provider_profile(provider_profile) do
    to_form(provider_profile_form_params(provider_profile), as: :provider_profile)
  end

  defp provider_profile_form_params(provider_profile) do
    configuration = provider_profile.configuration
    framing = Map.get(configuration, "framing", %{})
    tls = Map.get(configuration, "tls", %{})
    reconnect = Map.get(configuration, "reconnect", %{})
    scheduling = Map.get(configuration, "scheduling", %{})

    %{
      "display_name" => display_name(provider_profile, :provider_profile_id),
      "tcp_mode" => Map.get(configuration, "mode", "listen"),
      "direction" => Map.get(configuration, "direction", "downlink"),
      "host" => Map.get(configuration, "host", "0.0.0.0"),
      "port" => string_value(Map.get(configuration, "port", "")),
      "framing_mode" => Map.get(framing, "mode", "raw"),
      "frame_size" =>
        string_value(
          Map.get(framing, "fixed_message_bytes") ||
            Map.get(configuration, "fixed_message_bytes", "")
        ),
      "reconnect_policy" => Map.get(reconnect, "policy", "none"),
      "tls_enabled" => boolean_string(Map.get(tls, "enabled", false)),
      "scheduling_enabled" => boolean_string(scheduling != %{}),
      "scheduling_client" => Map.get(scheduling, "client", "simulator_http"),
      "scheduling_base_url" => Map.get(scheduling, "base_url", ""),
      "scheduling_api_token" => Map.get(scheduling, "api_token", ""),
      "scheduling_delivery_host" => Map.get(scheduling, "delivery_host", ""),
      "scheduling_run_id" => Map.get(scheduling, "run_id", "")
    }
  end

  defp tcp_configuration(params) do
    with {:ok, mode} <- tcp_mode(params["tcp_mode"]),
         {:ok, direction} <- direction(params["direction"]),
         {:ok, host} <- required_text(params["host"], "Host is required."),
         {:ok, port} <- port(params["port"]),
         {:ok, framing_mode} <- framing_mode(params["framing_mode"]),
         {:ok, frame_size} <- frame_size(params["frame_size"], framing_mode),
         {:ok, reconnect_policy} <- reconnect_policy(params["reconnect_policy"], mode),
         {:ok, tls_enabled} <- boolean(params["tls_enabled"]),
         {:ok, scheduling} <- scheduling_configuration(params) do
      {:ok,
       build_tcp_configuration(
         mode,
         direction,
         host,
         port,
         framing_mode,
         frame_size,
         reconnect_policy,
         tls_enabled
       )
       |> maybe_put_scheduling(scheduling)}
    end
  end

  defp build_tcp_configuration(
         mode,
         direction,
         host,
         port,
         framing_mode,
         frame_size,
         reconnect_policy,
         tls_enabled
       ) do
    %{
      "adapter" => "tcp_socket",
      "mode" => mode,
      "direction" => direction,
      "host" => host,
      "port" => port,
      "framing" => compact(%{"mode" => framing_mode, "fixed_message_bytes" => frame_size}),
      "tls" => %{"enabled" => tls_enabled},
      "reconnect" => reconnect_configuration(mode, reconnect_policy)
    }
    |> maybe_put_fixed_message_bytes(frame_size)
  end

  defp maybe_put_fixed_message_bytes(configuration, nil), do: configuration

  defp maybe_put_fixed_message_bytes(configuration, frame_size) do
    Map.put(configuration, "fixed_message_bytes", frame_size)
  end

  defp reconnect_configuration("connect", policy), do: %{"policy" => policy}
  defp reconnect_configuration("listen", _policy), do: %{"policy" => "on_disconnect"}

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_put_scheduling(configuration, nil), do: configuration

  defp maybe_put_scheduling(configuration, scheduling),
    do: Map.put(configuration, "scheduling", scheduling)

  defp scheduling_configuration(%{"scheduling_enabled" => enabled} = params)
       when enabled in [true, "true"] do
    with {:ok, client} <- scheduling_client(params["scheduling_client"]),
         {:ok, base_url} <- provider_base_url(params["scheduling_base_url"]),
         {:ok, delivery_host} <-
           required_text(
             params["scheduling_delivery_host"],
             "Cadence telemetry delivery host is required."
           ) do
      {:ok,
       compact(%{
         "client" => client,
         "base_url" => base_url,
         "api_token" => normalize_text(params["scheduling_api_token"]),
         "delivery_host" => delivery_host,
         "run_id" => normalize_text(params["scheduling_run_id"])
       })}
    end
  end

  defp scheduling_configuration(_params), do: {:ok, nil}

  defp scheduling_client("simulator_http"), do: {:ok, "simulator_http"}
  defp scheduling_client(_value), do: {:error, "Provider integration is invalid."}

  defp provider_base_url(value) do
    with base_url when is_binary(base_url) <- normalize_text(value),
         %URI{scheme: scheme, host: host}
         when scheme in ["http", "https"] and is_binary(host) <- URI.parse(base_url) do
      {:ok, base_url}
    else
      _other -> {:error, "Provider API URL must be an absolute HTTP or HTTPS URL."}
    end
  end

  defp tcp_mode("listen"), do: {:ok, "listen"}
  defp tcp_mode("connect"), do: {:ok, "connect"}
  defp tcp_mode(_value), do: {:error, "TCP mode is invalid."}

  defp direction("downlink"), do: {:ok, "downlink"}
  defp direction("uplink"), do: {:ok, "uplink"}
  defp direction("bidirectional"), do: {:ok, "bidirectional"}
  defp direction(_value), do: {:error, "Direction is invalid."}

  defp required_text(value, message) do
    case normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp port(value) do
    case parse_integer(value) do
      {:ok, port} when port >= 1 and port <= 65_535 -> {:ok, port}
      _other -> {:error, "Port must be an integer from 1 to 65535."}
    end
  end

  defp framing_mode("raw"), do: {:ok, "raw"}
  defp framing_mode("fixed_size"), do: {:ok, "fixed_size"}
  defp framing_mode("line_delimited"), do: {:ok, "line_delimited"}
  defp framing_mode(_value), do: {:error, "Framing mode is invalid."}

  defp frame_size(value, "fixed_size") do
    case parse_integer(value) do
      {:ok, frame_size} when frame_size > 0 -> {:ok, frame_size}
      _other -> {:error, "Fixed frame size must be a positive integer."}
    end
  end

  defp frame_size(_value, _framing_mode), do: {:ok, nil}

  defp reconnect_policy(value, "connect") do
    case normalize_text(value) || "always" do
      policy when policy in ["none", "always", "on_disconnect"] -> {:ok, policy}
      _other -> {:error, "Reconnect policy is invalid."}
    end
  end

  defp reconnect_policy(_value, "listen"), do: {:ok, "on_disconnect"}

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(true), do: {:ok, true}
  defp boolean(false), do: {:ok, false}
  defp boolean(_value), do: {:error, "TLS setting is invalid."}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_value), do: :error

  defp tcp_mode_options do
    [{"TCP server (listen)", "listen"}, {"TCP client (connect)", "connect"}]
  end

  defp tcp_direction_options do
    [{"Downlink", "downlink"}, {"Uplink", "uplink"}, {"Bidirectional", "bidirectional"}]
  end

  defp framing_options do
    [
      {"Raw bytes", "raw"},
      {"Fixed-size frames", "fixed_size"},
      {"Line-delimited", "line_delimited"}
    ]
  end

  defp reconnect_policy_options do
    [
      {"Always reconnect", "always"},
      {"Reconnect after disconnect", "on_disconnect"},
      {"Do not reconnect", "none"}
    ]
  end

  defp tls_options, do: [{"Disabled", "false"}, {"Enabled", "true"}]
  defp enabled_options, do: [{"Disabled", "false"}, {"Enabled", "true"}]
  defp scheduling_client_options, do: [{"Cadence Ground Network Simulator", "simulator_http"}]

  defp host_label(form) do
    if tcp_client?(form), do: "Remote Host", else: "Bind Host / Interface"
  end

  defp port_label(form) do
    if tcp_client?(form), do: "Remote Port", else: "Listen Port"
  end

  defp tcp_client?(form), do: form_value(form, :tcp_mode) == "connect"

  defp preview_configuration(form) do
    params = %{
      "tcp_mode" => form_value(form, :tcp_mode),
      "direction" => form_value(form, :direction),
      "host" => form_value(form, :host),
      "port" => form_value(form, :port),
      "framing_mode" => form_value(form, :framing_mode),
      "frame_size" => form_value(form, :frame_size),
      "reconnect_policy" => form_value(form, :reconnect_policy),
      "tls_enabled" => form_value(form, :tls_enabled),
      "scheduling_enabled" => form_value(form, :scheduling_enabled),
      "scheduling_client" => form_value(form, :scheduling_client),
      "scheduling_base_url" => form_value(form, :scheduling_base_url),
      "scheduling_api_token" => form_value(form, :scheduling_api_token),
      "scheduling_delivery_host" => form_value(form, :scheduling_delivery_host),
      "scheduling_run_id" => form_value(form, :scheduling_run_id)
    }

    case tcp_configuration(params) do
      {:ok, configuration} -> configuration
      {:error, _message} -> %{"adapter" => "tcp_socket"}
    end
  end

  defp form_value(form, field) do
    Form.input_value(form, field)
  end

  defp assign_form_state(%{assigns: %{live_action: :version}} = socket, %{
         "provider_profile_id" => provider_profile_id
       }) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.fetch_provider_profile(
           scope.organization_id,
           mission.mission_id,
           provider_profile_id
         ) do
      {:ok, provider_profile} ->
        socket
        |> assign(:page_title, "New Provider Version")
        |> assign(:nav_item, :comms_providers)
        |> assign(:provider_profile, provider_profile)
        |> assign(
          :return_to,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{provider_profile_id}"
        )
        |> assign(:heading, "New Provider Version")
        |> assign(:submit_label, "Create New Version")
        |> assign(:form, form_from_provider_profile(provider_profile))

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Provider profile not found.")
        |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/providers")
    end
  end

  defp assign_form_state(socket, _params) do
    %{current_mission: mission} = socket.assigns

    socket
    |> assign(:page_title, "New Provider")
    |> assign(:nav_item, :comms_providers)
    |> assign(:provider_profile, nil)
    |> assign(:return_to, ~p"/missions/#{mission.mission_id}/comms/providers")
    |> assign(:heading, "New Provider")
    |> assign(:submit_label, "Create Provider")
    |> assign(:form, empty_form())
  end

  defp save_provider_profile(
         %{assigns: %{live_action: :version, provider_profile: provider_profile}},
         organization_id,
         mission,
         display_name,
         configuration
       ) do
    Cadence.version_provider_profile(
      organization_id,
      mission.mission_id,
      provider_profile.provider_profile_id,
      %{
        adapter_key: :tcp_socket,
        configuration: configuration,
        metadata: %{"display_name" => display_name}
      }
    )
  end

  defp save_provider_profile(_socket, organization_id, mission, display_name, configuration) do
    provider_profile =
      ProviderProfile.new(%{
        mission_id: mission.mission_id,
        adapter_key: :tcp_socket,
        configuration: configuration,
        metadata: %{"display_name" => display_name}
      })

    Cadence.persist_provider_profile(organization_id, provider_profile)
  end

  defp provider_profile_return_path(
         %{assigns: %{live_action: :version, provider_profile: profile}},
         mission_id
       ) do
    ~p"/missions/#{mission_id}/comms/providers/#{profile.provider_profile_id}"
  end

  defp provider_profile_return_path(_socket, mission_id) do
    ~p"/missions/#{mission_id}/comms/providers"
  end

  defp string_value(nil), do: ""
  defp string_value(value), do: to_string(value)

  defp boolean_string(true), do: "true"
  defp boolean_string(_value), do: "false"
end
