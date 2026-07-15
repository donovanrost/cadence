defmodule CadenceWeb.CommsProviderNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Ground Network Provider")
     |> assign(:nav_item, :comms_providers)
     |> assign(:selected_provider_type, "simulator")
     |> assign(:form, to_form(default_params(), as: :provider))}
  end

  @impl true
  def handle_event("validate", %{"provider" => params}, socket) do
    {:noreply,
     socket
     |> assign(:selected_provider_type, params["provider_type"])
     |> assign(:form, to_form(params, as: :provider))}
  end

  @impl true
  def handle_event("save", %{"provider" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, attrs} <- provider_attrs(params, mission.mission_id),
         provider <- MissionProvider.new(attrs),
         {:ok, provider} <- GroundNetworks.persist_provider(scope.organization_id, provider) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
       )}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  rescue
    error in ArgumentError ->
      {:noreply, put_flash(socket, :error, error.message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-provider-new-page" class="max-w-2xl space-y-6">
      <.page_header
        title="New Ground Network Provider"
        subtitle="Connect Cadence to a provider control plane without exposing its underlying telemetry transport."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Providers", ~p"/missions/#{@current_mission.mission_id}/comms/providers"},
          {"New", nil}
        ]}
      />

      <.form
        for={@form}
        id="mission-provider-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-8"
      >
        <.form_section number="01" title="Provider Identity">
          <.input field={@form[:display_name]} type="text" label="Display Name" required />
          <.input
            field={@form[:provider_type]}
            type="select"
            label="Provider Type"
            options={provider_type_options()}
            required
          />
        </.form_section>

        <.form_section number="02" title="Control Plane">
          <div
            :if={@selected_provider_type == "simulator"}
            id="simulator-provider-guidance"
            class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"
          >
            Cadence will use the simulator's provider API for validation, inventory discovery,
            scheduling, and delivery profile negotiation. Transport endpoints are discovered later.
          </div>
          <.input
            field={@form[:base_url]}
            type="url"
            label="Provider API Base URL"
            placeholder="http://127.0.0.1:4101"
            required
          />
          <.input
            field={@form[:credential_ref]}
            type="text"
            label="Credential Reference"
            placeholder="config://ground-network-simulator"
            required
          />
          <p id="provider-credential-note" class="text-xs text-base-content/60">
            Store only a runtime reference such as <span class="font-mono">config://...</span>
            or <span class="font-mono">env://...</span>. Cadence never persists the secret here.
          </p>
          <.input
            field={@form[:environment_ref]}
            type="text"
            label="Provider Environment"
            placeholder="local-demo"
            required
          />
        </.form_section>

        <.form_actions
          submit="Create Provider"
          cancel_navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
        />
      </.form>
    </div>
    """
  end

  defp default_params do
    %{
      "display_name" => "Ground Network Simulator",
      "provider_type" => "simulator",
      "base_url" => "http://127.0.0.1:4101",
      "credential_ref" => "config://ground-network-simulator",
      "environment_ref" => "local-demo"
    }
  end

  defp provider_attrs(params, mission_id) do
    with {:ok, display_name} <- required_text(params["display_name"], "Display name is required."),
         {:ok, provider_type} <- provider_type(params["provider_type"]),
         {:ok, base_url} <- valid_base_url(params["base_url"]),
         {:ok, credential_ref} <-
           required_text(params["credential_ref"], "Credential reference is required."),
         {:ok, environment_ref} <-
           required_text(params["environment_ref"], "Provider environment is required.") do
      {:ok,
       %{
         mission_id: mission_id,
         display_name: display_name,
         provider_type: provider_type,
         client_key: MissionProvider.client_for(provider_type),
         base_url: base_url,
         credential_ref: credential_ref,
         environment_ref: environment_ref
       }}
    end
  end

  defp provider_type("simulator"), do: {:ok, :simulator}
  defp provider_type(_value), do: {:error, "Select a supported provider type."}

  defp valid_base_url(value) do
    with {:ok, value} <- required_text(value, "Provider API base URL is required."),
         %URI{scheme: scheme, host: host}
         when scheme in ["http", "https"] and host not in [nil, ""] <-
           URI.parse(value) do
      {:ok, value}
    else
      _other -> {:error, "Provider API base URL must be a valid HTTP or HTTPS URL."}
    end
  end

  defp required_text(value, message) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, message}
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_text(_value, message), do: {:error, message}

  defp provider_type_options, do: [{"Ground Network Simulator", "simulator"}]

  defp format_error(%Ecto.Changeset{} = changeset) do
    CadenceWeb.CommsComponents.format_error(changeset)
  end

  defp format_error(reason), do: "Could not create provider: #{inspect(reason)}"
end
