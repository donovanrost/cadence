defmodule CadenceWeb.CommsRoutingNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.RoutingRule

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)
    transports = Cadence.list_transports(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "New Routing Rule")
     |> assign(:nav_item, :comms_routing)
     |> assign(:spacecraft, spacecraft)
     |> assign(:transports, transports)
     |> assign(:form, to_form(empty_form_params(params), as: :routing_rule))}
  end

  @impl true
  def handle_event("validate", %{"routing_rule" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :routing_rule))}
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

      case Cadence.create_routing_rule(scope.organization_id, routing_rule) do
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
    <div id="comms-routing-new-page" class="space-y-6 max-w-2xl">
      <div class="border-b border-primary/20 pb-4">
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing"}
          class="hud-label text-base-content/50 hover:text-primary"
        >
          &larr; Routing
        </.link>
        <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
          New Routing Rule
        </h1>
        <p class="mt-2 max-w-2xl text-sm text-base-content/60">
          Declare durable spacecraft use of a transport for a purpose and direction. Contacts and runtime Links are handled later.
        </p>
      </div>

      <.form
        for={@form}
        id="routing-rule-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <section class="space-y-4">
          <div class="flex items-center gap-3">
            <span class="hud-label text-primary/70">01</span>
            <h2 class="hud-label">Intent</h2>
            <div class="flex-1 h-px bg-base-300/60"></div>
          </div>
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
          <.input field={@form[:purpose_label]} type="text" label="Purpose" required />
        </section>

        <section class="space-y-4">
          <div class="flex items-center gap-3">
            <span class="hud-label text-primary/70">02</span>
            <h2 class="hud-label">Spacecraft And Transport</h2>
            <div class="flex-1 h-px bg-base-300/60"></div>
          </div>
          <.input
            field={@form[:spacecraft_id]}
            type="select"
            label="Spacecraft"
            options={spacecraft_options(@spacecraft)}
            required
          />
          <.input
            field={@form[:transport_ref]}
            type="select"
            label="Transport"
            options={transport_options(@transports)}
            required
          />
        </section>

        <section class="space-y-4">
          <div class="flex items-center gap-3">
            <span class="hud-label text-primary/70">03</span>
            <h2 class="hud-label">Routing Policy</h2>
            <div class="flex-1 h-px bg-base-300/60"></div>
          </div>
          <.input
            field={@form[:direction]}
            type="select"
            label="Direction"
            options={direction_options()}
            required
          />
          <.input field={@form[:role]} type="select" label="Role" options={role_options()} required />
        </section>

        <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
          <button type="submit" class="btn btn-primary hover-glow-cyan transition-glow">
            Create Routing Rule
          </button>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/routing"}
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
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

  defp spacecraft_options(spacecraft) do
    [{"Select spacecraft", ""} | Enum.map(spacecraft, &{&1.display_name, &1.spacecraft_id})]
  end

  defp transport_options(transports) do
    [
      {"Select transport", ""}
      | Enum.map(
          transports,
          &{"#{&1.display_name} (v#{&1.version})", "#{&1.transport_id}:#{&1.version}"}
        )
    ]
  end

  defp direction_options do
    [{"Inbound", "inbound"}, {"Outbound", "outbound"}, {"Bidirectional", "bidirectional"}]
  end

  defp role_options do
    [{"Primary", "primary"}, {"Candidate", "candidate"}, {"Contributing", "contributing"}]
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
