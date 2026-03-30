defmodule Cadence.MissionEvents.Entry do
  @moduledoc """
  Rebuildable mission-scoped timeline entry projected from canonical records.
  """

  @type category :: :operations | :health | :runtime | :transport
  @type kind ::
          :scheduled_contact_canceled
          | :realized_contact_ended_early
          | :limit_violation
          | :managed_action_requested
          | :downlink_record_combined
          | :downlink_observation_accepted
          | :downlink_selection_changed
  @type severity :: :info | :warning | :error | :critical
  @type source_record_kind ::
          :contact_action
          | :limit_event
          | :managed_action_request
          | :combined_downlink_record
          | :downlink_diagnostic
  @type subject_kind ::
          :scheduled_contact
          | :realized_contact
          | :telemetry_point
          | :capability_instance
          | :downlink_observation

  @type t :: %__MODULE__{
          mission_event_id: binary(),
          mission_id: binary(),
          occurred_at: DateTime.t(),
          category: category(),
          kind: kind(),
          severity: severity() | nil,
          status: binary() | nil,
          title: binary(),
          summary: binary() | nil,
          source_record_kind: source_record_kind(),
          source_record_id: binary(),
          subject_kind: subject_kind() | nil,
          subject_id: binary() | nil,
          correlation_key: binary() | nil,
          spacecraft_id: binary() | nil,
          source_endpoint_ref: binary() | nil,
          scheduled_contact_id: binary() | nil,
          realized_contact_id: binary() | nil,
          path_id: binary() | nil,
          capability_instance_id: binary() | nil,
          activation_id: binary() | nil,
          actor: map(),
          metadata: map()
        }

  defstruct [
    :mission_event_id,
    :mission_id,
    :occurred_at,
    :category,
    :kind,
    :severity,
    :status,
    :title,
    :summary,
    :source_record_kind,
    :source_record_id,
    :subject_kind,
    :subject_id,
    :correlation_key,
    :spacecraft_id,
    :source_endpoint_ref,
    :scheduled_contact_id,
    :realized_contact_id,
    :path_id,
    :capability_instance_id,
    :activation_id,
    actor: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    mission_id = fetch_required(attrs, :mission_id)

    source_record_kind =
      attrs
      |> fetch_required(:source_record_kind)
      |> normalize_atom()

    source_record_id = fetch_required(attrs, :source_record_id)

    %__MODULE__{
      mission_event_id:
        Map.get(
          attrs,
          :mission_event_id,
          build_mission_event_id(mission_id, source_record_kind, source_record_id)
        ),
      mission_id: mission_id,
      occurred_at: fetch_required(attrs, :occurred_at),
      category: attrs |> fetch_required(:category) |> normalize_atom(),
      kind: attrs |> fetch_required(:kind) |> normalize_atom(),
      severity:
        attrs |> Map.get(:severity, Map.get(attrs, "severity")) |> normalize_optional_atom(),
      status: normalize_optional_binary(Map.get(attrs, :status, Map.get(attrs, "status"))),
      title: fetch_required(attrs, :title),
      summary: normalize_optional_binary(Map.get(attrs, :summary, Map.get(attrs, "summary"))),
      source_record_kind: source_record_kind,
      source_record_id: source_record_id,
      subject_kind:
        attrs
        |> Map.get(:subject_kind, Map.get(attrs, "subject_kind"))
        |> normalize_optional_atom(),
      subject_id:
        normalize_optional_binary(Map.get(attrs, :subject_id, Map.get(attrs, "subject_id"))),
      correlation_key:
        normalize_optional_binary(
          Map.get(attrs, :correlation_key, Map.get(attrs, "correlation_key"))
        ),
      spacecraft_id:
        normalize_optional_binary(Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id"))),
      source_endpoint_ref:
        normalize_optional_binary(
          Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref"))
        ),
      scheduled_contact_id:
        normalize_optional_binary(
          Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id"))
        ),
      realized_contact_id:
        normalize_optional_binary(
          Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id"))
        ),
      path_id: normalize_optional_binary(Map.get(attrs, :path_id, Map.get(attrs, "path_id"))),
      capability_instance_id:
        normalize_optional_binary(
          Map.get(attrs, :capability_instance_id, Map.get(attrs, "capability_instance_id"))
        ),
      activation_id:
        normalize_optional_binary(Map.get(attrs, :activation_id, Map.get(attrs, "activation_id"))),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{})),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec build_mission_event_id(binary(), source_record_kind(), binary()) :: binary()
  def build_mission_event_id(mission_id, source_record_kind, source_record_id)
      when is_binary(mission_id) and is_atom(source_record_kind) and
             is_binary(source_record_id) do
    "mission_event:" <>
      mission_id <> ":" <> Atom.to_string(source_record_kind) <> ":" <> source_record_id
  end

  defp fetch_required(attrs, key) when is_map(attrs) and is_atom(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(attrs, Atom.to_string(key))
    end
  end

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value), do: normalize_atom(value)

  defp normalize_optional_binary(nil), do: nil
  defp normalize_optional_binary(value) when is_binary(value), do: value
  defp normalize_optional_binary(value) when is_atom(value), do: Atom.to_string(value)
end
