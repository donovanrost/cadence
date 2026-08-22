defmodule Cadence.Limits.DefinitionLifecycleEvent do
  @moduledoc """
  Append-only lifecycle event for a governed limit definition becoming effective.
  """

  alias Cadence.Ids
  alias Cadence.Limits.Definition
  alias Cadence.Platform.Fingerprint

  @type event_type :: :registered | :activated | :superseded | :disabled | :retired | :unknown

  @type t :: %__MODULE__{
          limit_definition_lifecycle_event_id: binary(),
          definition_activation_key: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          point_id: binary(),
          limit_set_name: binary(),
          scope_type: atom() | binary() | nil,
          scope_ref: binary() | nil,
          realm: atom() | binary() | nil,
          event_type: event_type(),
          limit_definition_id: binary(),
          limit_definition_version: pos_integer(),
          previous_limit_definition_id: binary() | nil,
          previous_limit_definition_version: pos_integer() | nil,
          active_from: DateTime.t(),
          active_to: DateTime.t() | nil,
          reason: atom() | binary() | nil,
          observed_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :limit_definition_lifecycle_event_id,
    :definition_activation_key,
    :organization_id,
    :mission_id,
    :point_id,
    :limit_set_name,
    :scope_type,
    :scope_ref,
    :realm,
    :event_type,
    :limit_definition_id,
    :limit_definition_version,
    :previous_limit_definition_id,
    :previous_limit_definition_version,
    :active_from,
    :active_to,
    :reason,
    :observed_at,
    payload: %{}
  ]

  @event_types [:registered, :activated, :superseded, :disabled, :retired, :unknown]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    identity = activation_identity(attrs)
    observed_at = normalize_datetime(get_attr(attrs, :observed_at, DateTime.utc_now()))

    %__MODULE__{
      limit_definition_lifecycle_event_id:
        get_attr(attrs, :limit_definition_lifecycle_event_id) ||
          Ids.new("limit_definition_lifecycle_event"),
      definition_activation_key:
        get_attr(attrs, :definition_activation_key) || definition_activation_key(identity),
      organization_id: Map.get(identity, :organization_id),
      mission_id: Map.fetch!(identity, :mission_id),
      point_id: Map.fetch!(identity, :point_id),
      limit_set_name: Map.fetch!(identity, :limit_set_name),
      scope_type: Map.get(identity, :scope_type),
      scope_ref: Map.get(identity, :scope_ref),
      realm: Map.get(identity, :realm),
      event_type:
        attrs
        |> get_attr(:event_type, :registered)
        |> normalize_event_type(),
      limit_definition_id: get_attr(attrs, :limit_definition_id),
      limit_definition_version: get_attr(attrs, :limit_definition_version),
      previous_limit_definition_id: get_attr(attrs, :previous_limit_definition_id),
      previous_limit_definition_version: get_attr(attrs, :previous_limit_definition_version),
      active_from: normalize_datetime(get_attr(attrs, :active_from, observed_at)),
      active_to: normalize_datetime(get_attr(attrs, :active_to)),
      reason: get_attr(attrs, :reason),
      observed_at: observed_at,
      payload: get_attr(attrs, :payload, %{})
    }
  end

  @spec from_definition(Definition.t(), keyword()) :: t()
  def from_definition(%Definition{} = definition, opts \\ []) when is_list(opts) do
    definition
    |> attrs_from_definition(opts)
    |> new()
  end

  @spec attrs_from_definition(Definition.t(), keyword()) :: map()
  def attrs_from_definition(%Definition{} = definition, opts \\ []) when is_list(opts) do
    observed_at = Keyword.get_lazy(opts, :observed_at, &DateTime.utc_now/0)

    %{
      organization_id: Keyword.get(opts, :organization_id),
      mission_id: definition.mission_id,
      point_id: definition.point_id,
      limit_set_name: definition.limit_set_name,
      scope_type: Keyword.get(opts, :scope_type),
      scope_ref: Keyword.get(opts, :scope_ref),
      realm: Keyword.get(opts, :realm),
      event_type: Keyword.get(opts, :event_type, :registered),
      limit_definition_id: definition.limit_definition_id,
      limit_definition_version: definition.version,
      active_from: Keyword.get(opts, :active_from, observed_at),
      active_to: Keyword.get(opts, :active_to),
      reason: Keyword.get(opts, :reason, :definition_persisted),
      observed_at: observed_at,
      payload: Keyword.get(opts, :payload, %{})
    }
  end

  @spec definition_activation_key(map()) :: binary()
  def definition_activation_key(identity) when is_map(identity) do
    "limit_activation:" <>
      Fingerprint.url_sha256(%{
        organization_id: get_attr(identity, :organization_id),
        mission_id: get_attr(identity, :mission_id),
        point_id: get_attr(identity, :point_id),
        limit_set_name: get_attr(identity, :limit_set_name),
        scope_type: get_attr(identity, :scope_type),
        scope_ref: get_attr(identity, :scope_ref),
        realm: get_attr(identity, :realm)
      })
  end

  defp activation_identity(attrs) do
    %{
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      point_id: get_attr(attrs, :point_id),
      limit_set_name: get_attr(attrs, :limit_set_name, "DEFAULT"),
      scope_type: get_attr(attrs, :scope_type),
      scope_ref: get_attr(attrs, :scope_ref),
      realm: get_attr(attrs, :realm)
    }
  end

  defp normalize_event_type(value) when is_atom(value) and value in @event_types, do: value

  defp normalize_event_type(value) when is_binary(value) do
    Enum.find(@event_types, &(Atom.to_string(&1) == value)) || :unknown
  end

  defp normalize_event_type(_value), do: :unknown

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(%DateTime{} = datetime), do: truncate_datetime(datetime)

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> truncate_datetime(datetime)
      _error -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp truncate_datetime(%DateTime{} = datetime) do
    datetime = DateTime.truncate(datetime, :microsecond)
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(%_{} = attrs, key, default) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key, default)
  end

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
