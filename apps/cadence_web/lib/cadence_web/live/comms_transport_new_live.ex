defmodule CadenceWeb.CommsTransportNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.Transport
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Phoenix.HTML.Form

  @impl true
  def mount(_params, _session, socket) do
    %{current_mission: mission} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "New Transport")
     |> assign(:nav_item, :comms_transports)
     |> assign(:return_to, ~p"/missions/#{mission.mission_id}/comms/transports")
     |> assign(:form, to_form(empty_form_params(), as: :transport))}
  end

  @impl true
  def handle_event("validate", %{"transport" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :transport))}
  end

  @impl true
  def handle_event("save", %{"transport" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, configuration} <- TCPSocket.normalize_config(tcp_config_params(params)) do
      transport =
        Transport.new(%{
          mission_id: mission.mission_id,
          display_name: display_name,
          transport_kind: :tcp_socket,
          direction_capability: configuration["direction_capability"],
          adapter_key: :tcp_socket,
          configuration: configuration
        })

      case Cadence.persist_transport(scope.organization_id, transport) do
        {:ok, persisted} ->
          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/comms/transports/#{persisted.transport_id}"
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
    <div id="comms-transport-new-page" class="space-y-6 max-w-2xl">
      <.page_header
        title="New Transport"
        subtitle="Describe a durable capability for moving bytes. This setup does not mean a connection is currently open."
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
        <.identity_section form={@form} />
        <.capability_section form={@form} />
        <.framing_section form={@form} />
        <.reliability_section form={@form} />

        <details class="rounded border border-base-300 bg-base-100/40 p-4 text-sm">
          <summary class="cursor-pointer hud-label hover:text-primary">
            Configuration Preview
          </summary>
          <pre class="mt-3 overflow-x-auto font-mono text-xs text-base-content/70">{Jason.encode!(preview_configuration(@form), pretty: true)}</pre>
        </details>

        <.form_actions submit="Create Transport" cancel_navigate={@return_to} />
      </.form>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp identity_section(assigns) do
    ~H"""
    <.form_section number="01" title="Identity">
      <.input field={@form[:display_name]} type="text" label="Display Name" required />
      <.input
        field={@form[:transport_kind]}
        type="select"
        label="Transport Kind"
        options={transport_kind_options()}
        required
      />
    </.form_section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp capability_section(assigns) do
    ~H"""
    <.form_section number="02" title="TCP Socket Capability">
      <.input
        field={@form[:tcp_mode]}
        type="select"
        label="TCP Mode"
        options={tcp_mode_options()}
        required
      />
      <.input
        field={@form[:direction_capability]}
        type="select"
        label="Direction Capability"
        options={direction_capability_options()}
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

  defp empty_form_params do
    %{
      "display_name" => "",
      "transport_kind" => "tcp_socket",
      "tcp_mode" => "listen",
      "direction_capability" => "inbound",
      "host" => "0.0.0.0",
      "port" => "",
      "framing_mode" => "raw",
      "frame_size" => "",
      "reconnect_policy" => "none",
      "tls_enabled" => "false"
    }
  end

  defp tcp_config_params(params) do
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

  defp transport_kind_options do
    [{"TCP socket", "tcp_socket"}]
  end

  defp tcp_mode_options do
    [{"TCP server (listen)", "listen"}, {"TCP client (connect)", "connect"}]
  end

  defp direction_capability_options do
    [{"Inbound", "inbound"}, {"Outbound", "outbound"}, {"Bidirectional", "bidirectional"}]
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

  defp host_label(form) do
    if tcp_client?(form), do: "Remote Host", else: "Bind Host / Interface"
  end

  defp port_label(form) do
    if tcp_client?(form), do: "Remote Port", else: "Listen Port"
  end

  defp tcp_client?(form), do: form_value(form, :tcp_mode) == "connect"

  defp preview_configuration(form) do
    form
    |> preview_params()
    |> TCPSocket.normalize_config()
    |> case do
      {:ok, configuration} -> configuration
      {:error, _message} -> %{"adapter" => "tcp_socket"}
    end
  end

  defp preview_params(form) do
    %{
      "mode" => form_value(form, :tcp_mode),
      "direction_capability" => form_value(form, :direction_capability),
      "host" => form_value(form, :host),
      "port" => form_value(form, :port),
      "framing_mode" => form_value(form, :framing_mode),
      "frame_size" => form_value(form, :frame_size),
      "reconnect_policy" => form_value(form, :reconnect_policy),
      "tls_enabled" => form_value(form, :tls_enabled)
    }
  end

  defp form_value(form, field), do: Form.input_value(form, field)

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

  defp format_error(reason), do: "Failed to create transport: #{inspect(reason)}"
end
