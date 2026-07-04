defmodule Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent do
  @moduledoc """
  Append-only audit event for operator/system decisions on an observation identity.

  The observation identity state projection answers the current operational
  question. These events preserve why and when that projection changed.
  """

  alias Cadence.Ids
  alias Cadence.Telemetry.Storage.WriteContext

  @type decision :: :mark_canonical | :mark_conflict | :mark_superseded | :mark_advisory

  @type t :: %__MODULE__{
          decision_event_id: binary(),
          observation_identity_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          realm: WriteContext.realm() | binary(),
          replay_run_id: binary() | nil,
          data_source_id: binary() | nil,
          binding_id: binary() | nil,
          observable_id: binary(),
          point_id: binary(),
          spacecraft_id: binary() | nil,
          decision: decision(),
          decision_reason: binary(),
          actor_id: binary() | nil,
          actor_kind: binary() | nil,
          evidence_ref: map(),
          previous_state: map(),
          new_state: map(),
          occurred_at: DateTime.t()
        }

  defstruct [
    :decision_event_id,
    :observation_identity_id,
    :organization_id,
    :mission_id,
    :realm,
    :replay_run_id,
    :data_source_id,
    :binding_id,
    :observable_id,
    :point_id,
    :spacecraft_id,
    :decision,
    :decision_reason,
    :actor_id,
    :actor_kind,
    :occurred_at,
    evidence_ref: %{},
    previous_state: %{},
    new_state: %{}
  ]

  @decisions [:mark_canonical, :mark_conflict, :mark_superseded, :mark_advisory]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      decision_event_id:
        get_attr(attrs, :decision_event_id) ||
          Ids.new("telemetry_observation_identity_decision_event"),
      observation_identity_id: get_attr(attrs, :observation_identity_id),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      realm: get_attr(attrs, :realm),
      replay_run_id: get_attr(attrs, :replay_run_id),
      data_source_id: get_attr(attrs, :data_source_id),
      binding_id: get_attr(attrs, :binding_id),
      observable_id: get_attr(attrs, :observable_id),
      point_id: get_attr(attrs, :point_id),
      spacecraft_id: get_attr(attrs, :spacecraft_id),
      decision:
        attrs
        |> get_attr(:decision)
        |> normalize_decision(),
      decision_reason: get_attr(attrs, :decision_reason),
      actor_id: get_attr(attrs, :actor_id),
      actor_kind: get_attr(attrs, :actor_kind),
      evidence_ref: get_attr(attrs, :evidence_ref, %{}),
      previous_state: get_attr(attrs, :previous_state, %{}),
      new_state: get_attr(attrs, :new_state, %{}),
      occurred_at:
        attrs
        |> get_attr(:occurred_at, DateTime.utc_now())
        |> DateTime.truncate(:microsecond)
    }
  end

  defp normalize_decision(value) when value in @decisions, do: value

  defp normalize_decision(value) when is_binary(value) do
    Enum.find(@decisions, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported observation identity decision: #{inspect(value)}"
  end

  defp normalize_decision(value) do
    raise ArgumentError, "unsupported observation identity decision: #{inspect(value)}"
  end

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
