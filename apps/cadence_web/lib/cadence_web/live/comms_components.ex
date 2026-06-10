defmodule CadenceWeb.CommsComponents do
  @moduledoc false

  use Phoenix.Component

  import CadenceWeb.Components.Badges, only: [status_badge: 1]
  import CadenceWeb.Components.Card, only: [card: 1]

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :description, :string, required: true
  attr :navigate, :string, default: nil
  attr :status, :atom, default: :info

  def readiness_card(assigns) do
    ~H"""
    <.card accent={readiness_accent(@status)}>
      <div class="flex items-start justify-between gap-4">
        <p class="hud-label">{@title}</p>
        <.status_badge status={@status} />
      </div>
      <p class="mt-3 mc-value-large text-primary">{@value}</p>
      <p class="mt-2 text-sm text-base-content/60">{@description}</p>
      <.link
        :if={@navigate}
        navigate={@navigate}
        class="mt-4 inline-flex text-sm text-primary hover:underline"
      >
        Review configuration &rarr;
      </.link>
    </.card>
    """
  end

  defp readiness_accent(:ready), do: :success
  defp readiness_accent(:attention), do: :warning
  defp readiness_accent(:blocked), do: :error
  # Card with accent nil has no left border (previous code used border-l-transparent).
  defp readiness_accent(_), do: nil

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

  def human_atom(nil), do: "Not set"

  def human_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  def human_atom(value) when is_binary(value), do: value

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

  def format_error(:source_endpoint_not_found), do: "Selected telemetry identity was not found."
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
end
