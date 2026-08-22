defmodule Cadence.DataSources.SourceHealthEvent do
  @moduledoc """
  Append-only data-source health transition.

  This is a Data Sources subsystem fact. It can later be projected into the
  canonical operational event spine, but it remains useful on its own for source
  cache invalidation, operator diagnostics, and health recovery audits.
  """

  alias Cadence.Ids
  alias Cadence.Platform.Fingerprint

  @type source_health :: :healthy | :degraded | :unavailable | :unknown
  @type event_type :: :degraded | :recovered | :unavailable | :unknown

  @type t :: %__MODULE__{
          source_health_event_id: binary(),
          source_health_key: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          logical_source: atom() | binary(),
          data_source_id: binary(),
          source_binding_id: binary() | nil,
          realm: atom() | binary() | nil,
          replay_run_id: binary() | nil,
          dataset: binary() | nil,
          event_type: event_type(),
          source_health: source_health(),
          previous_source_health: source_health() | nil,
          reason: atom() | binary() | nil,
          observed_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :source_health_event_id,
    :source_health_key,
    :organization_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :source_binding_id,
    :realm,
    :replay_run_id,
    :dataset,
    :event_type,
    :source_health,
    :previous_source_health,
    :reason,
    :observed_at,
    payload: %{}
  ]

  @source_health_values [:healthy, :degraded, :unavailable, :unknown]
  @event_types [:degraded, :recovered, :unavailable, :unknown]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    source_health =
      attrs
      |> get_attr(:source_health, :unknown)
      |> normalize_source_health()

    previous_source_health =
      attrs
      |> get_attr(:previous_source_health)
      |> normalize_optional_source_health()

    identity = source_identity(attrs)

    %__MODULE__{
      source_health_event_id:
        get_attr(attrs, :source_health_event_id) || Ids.new("data_source_health_event"),
      source_health_key: get_attr(attrs, :source_health_key) || source_health_key(identity),
      organization_id: Map.get(identity, :organization_id),
      mission_id: Map.fetch!(identity, :mission_id),
      logical_source: Map.fetch!(identity, :logical_source),
      data_source_id: Map.fetch!(identity, :data_source_id),
      source_binding_id: Map.get(identity, :source_binding_id),
      realm: Map.get(identity, :realm),
      replay_run_id: Map.get(identity, :replay_run_id),
      dataset: Map.get(identity, :dataset),
      event_type:
        attrs
        |> get_attr(:event_type, event_type(source_health))
        |> normalize_event_type(),
      source_health: source_health,
      previous_source_health: previous_source_health,
      reason: get_attr(attrs, :reason),
      observed_at:
        attrs
        |> get_attr(:observed_at, DateTime.utc_now())
        |> truncate_datetime(),
      payload: get_attr(attrs, :payload, %{})
    }
  end

  @spec source_health_key(map()) :: binary()
  def source_health_key(identity) when is_map(identity) do
    "source_health:" <>
      Fingerprint.canonical_url_sha256(%{
        organization_id: get_attr(identity, :organization_id),
        mission_id: get_attr(identity, :mission_id),
        logical_source: get_attr(identity, :logical_source),
        data_source_id: get_attr(identity, :data_source_id),
        source_binding_id: get_attr(identity, :source_binding_id),
        realm: get_attr(identity, :realm),
        replay_run_id: get_attr(identity, :replay_run_id),
        dataset: get_attr(identity, :dataset)
      })
  end

  @spec event_type(source_health()) :: event_type()
  def event_type(:healthy), do: :recovered
  def event_type(:degraded), do: :degraded
  def event_type(:unavailable), do: :unavailable
  def event_type(:unknown), do: :unknown

  defp source_identity(attrs) do
    %{
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      logical_source: get_attr(attrs, :logical_source),
      data_source_id: get_attr(attrs, :data_source_id),
      source_binding_id: get_attr(attrs, :source_binding_id) || get_attr(attrs, :binding_id),
      realm: get_attr(attrs, :realm),
      replay_run_id: get_attr(attrs, :replay_run_id),
      dataset: get_attr(attrs, :dataset)
    }
  end

  defp normalize_source_health(value) when is_atom(value) and value in @source_health_values,
    do: value

  defp normalize_source_health(value) when is_binary(value) do
    Enum.find(@source_health_values, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported source_health: #{inspect(value)}"
  end

  defp normalize_source_health(value) do
    raise ArgumentError, "unsupported source_health: #{inspect(value)}"
  end

  defp normalize_optional_source_health(nil), do: nil
  defp normalize_optional_source_health(value), do: normalize_source_health(value)

  defp normalize_event_type(value) when is_atom(value) and value in @event_types, do: value

  defp normalize_event_type(value) when is_binary(value) do
    Enum.find(@event_types, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported event_type: #{inspect(value)}"
  end

  defp normalize_event_type(value) do
    raise ArgumentError, "unsupported event_type: #{inspect(value)}"
  end

  defp truncate_datetime(%DateTime{} = datetime) do
    datetime = DateTime.truncate(datetime, :microsecond)
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
