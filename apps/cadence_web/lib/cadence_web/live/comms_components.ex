defmodule CadenceWeb.CommsComponents do
  @moduledoc false

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  attr :current_mission, :map, required: true
  attr :active, :atom, required: true

  def comms_header(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}"}
          class="text-sm text-primary hover:underline"
        >
          &larr; {@current_mission.display_name}
        </.link>
      </div>

      <div>
        <p class="hud-label mb-2">Mission Setup</p>
        <h1 class="text-2xl font-bold text-base-content">Mission Network</h1>
        <p class="mt-1 max-w-3xl text-sm text-base-content/60">
          Configure shared ground-side connectivity, providers, and reusable link templates.
          Spacecraft-specific identity and byte interpretation stay with each spacecraft.
        </p>
      </div>

      <nav id="comms-section-nav" class="flex flex-wrap gap-2">
        <.comms_nav_link
          id="comms-nav-overview"
          active={@active == :overview}
          navigate={~p"/missions/#{@current_mission.mission_id}/comms"}
        >
          Mission Network
        </.comms_nav_link>
        <.comms_nav_link
          id="comms-nav-links"
          active={@active == :links}
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/links"}
        >
          Links
        </.comms_nav_link>
        <.comms_nav_link
          id="comms-nav-provider-profiles"
          active={@active == :provider_profiles}
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
        >
          Providers
        </.comms_nav_link>
        <.comms_nav_link
          id="comms-nav-path-templates"
          active={@active == :path_templates}
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates"}
        >
          Link Templates
        </.comms_nav_link>
        <.comms_nav_link
          id="comms-nav-validation"
          active={@active == :validation}
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/validation"}
        >
          Validation
        </.comms_nav_link>
        <.comms_nav_link
          id="comms-nav-advanced"
          active={@active in [:source_endpoints, :transport_profiles]}
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/advanced/runtime-identities"}
        >
          Advanced
        </.comms_nav_link>
      </nav>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :active, :boolean, required: true
  attr :navigate, :string, required: true
  slot :inner_block, required: true

  defp comms_nav_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class={[
        "btn btn-sm",
        if(@active, do: "btn-primary", else: "btn-ghost border border-base-300")
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :description, :string, required: true
  attr :navigate, :string, default: nil
  attr :status, :atom, default: :info

  def readiness_card(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-5">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label mb-2">{@title}</p>
            <p class="text-3xl font-bold font-mono">{@value}</p>
          </div>
          <span class={[
            "rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide",
            status_class(@status)
          ]}>
            {status_label(@status)}
          </span>
        </div>
        <p class="mt-3 text-sm text-base-content/60">{@description}</p>
        <.link :if={@navigate} navigate={@navigate} class="mt-4 text-sm text-primary hover:underline">
          Review configuration
        </.link>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :label, :string, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide",
      status_class(@status)
    ]}>
      {@label || status_label(@status)}
    </span>
    """
  end

  def display_name(%{metadata: metadata} = resource, fallback_field)
      when is_map(metadata) and is_atom(fallback_field) do
    Map.get(metadata, "display_name") ||
      Map.get(metadata, "name") ||
      Map.get(metadata, "label") ||
      Map.get(resource, fallback_field)
  end

  def display_name(resource, fallback_field) when is_map(resource) and is_atom(fallback_field) do
    Map.get(resource, fallback_field)
  end

  def human_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  def human_atom(value) when is_binary(value), do: value
  def human_atom(nil), do: "Not set"

  def profile_ref_label(ref, id_key) do
    id = Map.get(ref, id_key) || "unknown"
    version = Map.get(ref, "version") || 1
    "#{id} v#{version}"
  end

  def profile_ref_display_label(ref, id_key, profiles_by_id, fallback_field) do
    id = Map.get(ref, id_key) || "unknown"
    version = Map.get(ref, "version") || 1

    label =
      case Map.get(profiles_by_id, id) do
        {:archived, profile} -> "#{display_name(profile, fallback_field)} (archived)"
        profile when is_map(profile) -> display_name(profile, fallback_field)
        _missing -> id
      end

    "#{label} v#{version}"
  end

  def normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_text(_value), do: nil

  def parse_optional_integer(value) when is_binary(value) do
    case normalize_text(value) do
      nil ->
        {:ok, nil}

      value ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> {:ok, integer}
          _other -> {:error, "SCID must be a non-negative integer."}
        end
    end
  end

  def parse_optional_integer(_value), do: {:ok, nil}

  def parse_config_json(value) do
    case normalize_text(value) do
      nil ->
        {:ok, %{}}

      json ->
        case Jason.decode(json) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, decoded}

          {:ok, _decoded} ->
            {:error, "Configuration JSON must be an object."}

          {:error, _reason} ->
            {:error, "Configuration JSON is invalid."}
        end
    end
  end

  def format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  def format_error(:spacecraft_not_found), do: "Selected spacecraft was not found."

  def format_error(:contact_provider_profile_not_found),
    do: "Selected provider was not found."

  def format_error(:contact_transport_profile_not_found),
    do: "Selected protocol behavior was not found."

  def format_error(:source_endpoint_not_found), do: "Selected runtime identity was not found."
  def format_error(reason), do: "Failed to save comms configuration: #{inspect(reason)}"

  def adapter_options, do: [{"TCP Socket", "tcp_socket"}]

  def transport_family_options do
    [
      {"Heartbeat Monitor", "heartbeat_monitor"},
      {"Uplink Gateway", "uplink_gateway"}
    ]
  end

  def target_scope_options, do: [{"Path", "path"}, {"Transport", "transport"}]
  def direction_options, do: [{"Downlink", "downlink"}, {"Uplink", "uplink"}]

  def selection_role_options do
    [
      {"Selected", "selected"},
      {"Candidate", "candidate"},
      {"Contributing", "contributing"}
    ]
  end

  defp status_label(:ready), do: "Ready"
  defp status_label(:warning), do: "Needs Work"
  defp status_label(:missing), do: "Missing"
  defp status_label(:info), do: "Setup"

  defp status_class(:ready), do: "bg-success/20 text-success"
  defp status_class(:warning), do: "bg-warning/20 text-warning"
  defp status_class(:missing), do: "bg-error/20 text-error"
  defp status_class(:info), do: "bg-info/20 text-info"
end
