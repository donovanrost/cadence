defmodule Cadence.ContactPlanning.ContactRequirementVersion do
  @moduledoc "Immutable content version of one Contact Requirement."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @directions [:downlink, :uplink, :bidirectional, :tracking]
  @success_measures [:any_contact, :minimum_duration, :minimum_data_volume, :contact_count]
  @priorities [:routine, :high, :critical]

  @type direction :: :downlink | :uplink | :bidirectional | :tracking
  @type success_measure ::
          :any_contact | :minimum_duration | :minimum_data_volume | :contact_count
  @type priority :: :routine | :high | :critical

  @type t :: %__MODULE__{
          contact_requirement_version_id: binary(),
          contact_requirement_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          version: pos_integer(),
          spacecraft_id: binary(),
          service_direction: direction(),
          contact_intent: binary(),
          earliest_start: DateTime.t(),
          latest_end: DateTime.t(),
          success_measure: success_measure(),
          minimum_duration_seconds: pos_integer() | nil,
          preferred_duration_seconds: pos_integer() | nil,
          minimum_data_volume_bytes: pos_integer() | nil,
          contact_count: pos_integer(),
          minimum_separation_seconds: non_neg_integer(),
          priority: priority(),
          provider_constraints_document: map(),
          station_constraints_document: map(),
          policy_constraints_document: map(),
          approval_policy_document: map(),
          rationale: binary(),
          metadata: map(),
          content_sha256: binary(),
          created_by: binary(),
          created_at: DateTime.t()
        }

  defstruct [
    :contact_requirement_version_id,
    :contact_requirement_id,
    :organization_id,
    :mission_id,
    :version,
    :spacecraft_id,
    :service_direction,
    :contact_intent,
    :earliest_start,
    :latest_end,
    :success_measure,
    :minimum_duration_seconds,
    :preferred_duration_seconds,
    :minimum_data_volume_bytes,
    :contact_count,
    :minimum_separation_seconds,
    :priority,
    :provider_constraints_document,
    :station_constraints_document,
    :policy_constraints_document,
    :approval_policy_document,
    :rationale,
    :metadata,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec directions() :: [direction()]
  def directions, do: @directions

  @spec success_measures() :: [success_measure()]
  def success_measures, do: @success_measures

  @spec priorities() :: [priority()]
  def priorities, do: @priorities

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    version =
      %__MODULE__{
        contact_requirement_version_id:
          value(attrs, :contact_requirement_version_id, Ids.new("contact_requirement_version")),
        contact_requirement_id: required(attrs, :contact_requirement_id),
        organization_id: required(attrs, :organization_id),
        mission_id: required(attrs, :mission_id),
        version: positive(value(attrs, :version, 1), :version),
        spacecraft_id: required(attrs, :spacecraft_id),
        service_direction:
          attrs
          |> value(:service_direction, :downlink)
          |> normalize_atom(@directions, :service_direction),
        contact_intent: required(attrs, :contact_intent),
        earliest_start: datetime(value(attrs, :earliest_start), :earliest_start),
        latest_end: datetime(value(attrs, :latest_end), :latest_end),
        success_measure:
          attrs
          |> value(:success_measure, :any_contact)
          |> normalize_atom(@success_measures, :success_measure),
        minimum_duration_seconds:
          optional_positive(value(attrs, :minimum_duration_seconds), :minimum_duration_seconds),
        preferred_duration_seconds:
          optional_positive(
            value(attrs, :preferred_duration_seconds),
            :preferred_duration_seconds
          ),
        minimum_data_volume_bytes:
          optional_positive(
            value(attrs, :minimum_data_volume_bytes),
            :minimum_data_volume_bytes
          ),
        contact_count: positive(value(attrs, :contact_count, 1), :contact_count),
        minimum_separation_seconds:
          non_negative(
            value(attrs, :minimum_separation_seconds, 0),
            :minimum_separation_seconds
          ),
        priority:
          attrs
          |> value(:priority, :routine)
          |> normalize_atom(@priorities, :priority),
        provider_constraints_document:
          document(value(attrs, :provider_constraints_document, %{}), :provider_constraints),
        station_constraints_document:
          document(value(attrs, :station_constraints_document, %{}), :station_constraints),
        policy_constraints_document:
          document(value(attrs, :policy_constraints_document, %{}), :policy_constraints),
        approval_policy_document:
          document(
            value(attrs, :approval_policy_document, %{"mode" => "manual"}),
            :approval_policy
          ),
        rationale: string(value(attrs, :rationale, ""), :rationale),
        metadata: document(value(attrs, :metadata, %{}), :metadata),
        content_sha256: value(attrs, :content_sha256),
        created_by: required(attrs, :created_by),
        created_at: datetime(value(attrs, :created_at, DateTime.utc_now()), :created_at)
      }
      |> validate_time_range()
      |> validate_duration_order()
      |> validate_success_measure()

    %__MODULE__{
      version
      | content_sha256: version.content_sha256 || content_sha256(version)
    }
  end

  @spec content_document(t()) :: map()
  def content_document(%__MODULE__{} = version) do
    %{
      "spacecraft_id" => version.spacecraft_id,
      "service_direction" => Atom.to_string(version.service_direction),
      "contact_intent" => version.contact_intent,
      "earliest_start" => DateTime.to_iso8601(version.earliest_start),
      "latest_end" => DateTime.to_iso8601(version.latest_end),
      "success_measure" => Atom.to_string(version.success_measure),
      "minimum_duration_seconds" => version.minimum_duration_seconds,
      "preferred_duration_seconds" => version.preferred_duration_seconds,
      "minimum_data_volume_bytes" => version.minimum_data_volume_bytes,
      "contact_count" => version.contact_count,
      "minimum_separation_seconds" => version.minimum_separation_seconds,
      "priority" => Atom.to_string(version.priority),
      "provider_constraints" => version.provider_constraints_document,
      "station_constraints" => version.station_constraints_document,
      "policy_constraints" => version.policy_constraints_document,
      "approval_policy" => version.approval_policy_document,
      "rationale" => version.rationale,
      "metadata" => version.metadata
    }
  end

  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{} = version) do
    version
    |> content_document()
    |> JsonDocument.encode()
    |> then(&:erlang.term_to_binary(&1, [:deterministic]))
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_time_range(%__MODULE__{} = version) do
    if DateTime.before?(version.earliest_start, version.latest_end),
      do: version,
      else: raise(ArgumentError, "latest_end must be after earliest_start")
  end

  defp validate_duration_order(%__MODULE__{} = version) do
    case {version.minimum_duration_seconds, version.preferred_duration_seconds} do
      {minimum, preferred}
      when is_integer(minimum) and is_integer(preferred) and preferred < minimum ->
        raise ArgumentError, "preferred_duration_seconds must not be below the minimum"

      _other ->
        version
    end
  end

  defp validate_success_measure(%__MODULE__{success_measure: :minimum_duration} = version) do
    if version.minimum_duration_seconds,
      do: version,
      else: raise(ArgumentError, "minimum_duration_seconds is required")
  end

  defp validate_success_measure(%__MODULE__{success_measure: :minimum_data_volume} = version) do
    if version.minimum_data_volume_bytes,
      do: version,
      else: raise(ArgumentError, "minimum_data_volume_bytes is required")
  end

  defp validate_success_measure(%__MODULE__{} = version), do: version

  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)

  defp datetime(%NaiveDateTime{} = item, _field) do
    item |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:microsecond)
  end

  defp datetime(item, field) when is_binary(item) do
    case DateTime.from_iso8601(item) do
      {:ok, parsed, _offset} ->
        DateTime.truncate(parsed, :microsecond)

      _other ->
        case NaiveDateTime.from_iso8601(item) do
          {:ok, parsed} -> datetime(parsed, field)
          _other -> raise ArgumentError, "#{field} must be an ISO 8601 UTC timestamp"
        end
    end
  end

  defp datetime(_item, field), do: raise(ArgumentError, "#{field} is required")

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp string(item, _field) when is_binary(item), do: item
  defp string(_item, field), do: raise(ArgumentError, "#{field} must be a string")

  defp document(item, _field) when is_map(item), do: JsonDocument.encode(item)
  defp document(_item, field), do: raise(ArgumentError, "#{field} must be an object")

  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")

  defp optional_positive(nil, _field), do: nil
  defp optional_positive(item, field), do: positive(item, field)

  defp non_negative(item, _field) when is_integer(item) and item >= 0, do: item
  defp non_negative(_item, field), do: raise(ArgumentError, "#{field} must not be negative")

  defp normalize_atom(item, allowed, field) when is_atom(item) do
    if item in allowed,
      do: item,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(item)}")
  end

  defp normalize_atom(item, allowed, field) when is_binary(item) do
    Enum.find(allowed, &(Atom.to_string(&1) == item)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(item)}"
  end

  defp normalize_atom(item, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(item)}")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
