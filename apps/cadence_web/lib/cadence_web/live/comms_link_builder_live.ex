defmodule CadenceWeb.CommsLinkBuilderLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    form_params = empty_form_params()

    {:ok,
     socket
     |> assign(:page_title, "New Shared Mission Link")
     |> assign(:nav_item, :comms)
     |> assign(:form, to_form(form_params, as: :mission_link))}
  end

  @impl true
  def handle_event("validate", %{"mission_link" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(normalize_form_params(params), as: :mission_link))}
  end

  @impl true
  def handle_event("save", %{"mission_link" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Cadence.create_shared_link(
           scope.organization_id,
           mission.mission_id,
           normalize_form_params(params)
         ) do
      {:ok, %{path_templates: path_templates}} ->
        {:noreply,
         socket
         |> put_flash(:info, result_message(path_templates))
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/comms/link-templates")}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-link-builder-page" class="space-y-6 max-w-4xl">
      <.comms_header current_mission={@current_mission} active={:links} />

      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Link Templates
        </.link>
        <h1 class="mt-1 text-2xl font-bold text-base-content">New Shared Mission Link</h1>
        <p class="mt-1 max-w-3xl text-sm text-base-content/60">
          Create the mission-owned network path in one flow. Cadence will create the
          provider, optional protocol behavior, and reusable link template records behind
          the scenes.
        </p>
      </div>

      <.form
        for={@form}
        id="mission-link-builder-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-5"
      >
        <section class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 space-y-4">
            <div>
              <p class="hud-label mb-2">Mission Link</p>
              <h2 class="font-semibold">Reusable connectivity definition</h2>
              <p class="mt-1 text-sm text-base-content/60">
                This stays unassigned until it is applied to spacecraft from readiness or
                link assignment workflows.
              </p>
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <.input field={@form[:display_name]} type="text" label="Link Name" required />
              <.input
                field={@form[:direction]}
                type="select"
                label="Direction"
                options={builder_direction_options()}
                required
              />
              <.input
                field={@form[:selection_role]}
                type="select"
                label="Assignment Role"
                options={selection_role_options()}
                required
              />
              <.input
                field={@form[:provider_path_ref]}
                type="text"
                label="Provider Path Ref"
              />
            </div>
          </div>
        </section>

        <section class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 space-y-4">
            <div>
              <p class="hud-label mb-2">Provider</p>
              <h2 class="font-semibold">TCP ground connection</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Configure how Cadence reaches or listens for the ground-side network path.
              </p>
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:tcp_mode]}
                type="select"
                label="TCP Mode"
                options={tcp_mode_options()}
                required
              />
              <.input field={@form[:host]} type="text" label={host_label(@form)} required />
              <.input field={@form[:port]} type="number" label={port_label(@form)} required />
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
                label="Fixed Frame Size"
              />
              <.input
                field={@form[:tls_enabled]}
                type="select"
                label="TLS"
                options={tls_options()}
                required
              />
            </div>
          </div>
        </section>

        <section class="card bg-base-200 border border-base-300">
          <div class="card-body p-5 space-y-4">
            <div>
              <p class="hud-label mb-2">Protocol Behavior</p>
              <h2 class="font-semibold">Optional path-level behavior</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Add reusable path behavior here. Spacecraft byte interpretation remains on
                spacecraft pages.
              </p>
            </div>

            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:heartbeat_enabled]}
                type="select"
                label="Heartbeat Monitor"
                options={enabled_options()}
                required
              />
              <.input
                field={@form[:heartbeat_interval_ms]}
                type="number"
                label="Heartbeat Interval (ms)"
              />
            </div>
          </div>
        </section>

        <div class="flex items-center gap-3">
          <button id="mission-link-builder-submit" type="submit" class="btn btn-primary">
            Create Shared Link
          </button>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates"}
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form_params do
    %{
      "display_name" => "",
      "direction" => "downlink",
      "selection_role" => "selected",
      "provider_path_ref" => "",
      "tcp_mode" => "listen",
      "host" => "0.0.0.0",
      "port" => "",
      "framing_mode" => "raw",
      "frame_size" => "",
      "tls_enabled" => "false",
      "heartbeat_enabled" => "true",
      "heartbeat_interval_ms" => "1000"
    }
  end

  defp normalize_form_params(params) do
    Map.merge(empty_form_params(), params)
  end

  defp result_message([_path_template]), do: "Created shared mission link."

  defp result_message(path_templates) do
    "Created shared mission link with #{length(path_templates)} templates."
  end

  defp host_label(form) do
    if form.params["tcp_mode"] == "connect", do: "Remote Host", else: "Bind Host / Interface"
  end

  defp port_label(form) do
    if form.params["tcp_mode"] == "connect", do: "Remote Port", else: "Listen Port"
  end

  defp builder_direction_options do
    [{"Downlink", "downlink"}, {"Uplink", "uplink"}, {"Bidirectional", "bidirectional"}]
  end

  defp tcp_mode_options do
    [{"TCP server (listen)", "listen"}, {"TCP client (connect)", "connect"}]
  end

  defp framing_options do
    [
      {"Raw bytes", "raw"},
      {"Fixed-size frames", "fixed_size"},
      {"Line-delimited", "line_delimited"}
    ]
  end

  defp tls_options, do: [{"Disabled", "false"}, {"Enabled", "true"}]
  defp enabled_options, do: [{"Enabled", "true"}, {"Disabled", "false"}]
end
