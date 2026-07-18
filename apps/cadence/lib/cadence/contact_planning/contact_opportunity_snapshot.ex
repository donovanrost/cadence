defmodule Cadence.ContactPlanning.ContactOpportunitySnapshot do
  @moduledoc "Immutable normalized provider Opportunity captured for mission planning."

  alias Cadence.Ids

  @availability [:available, :limited, :unavailable]

  @type t :: %__MODULE__{
          contact_opportunity_snapshot_id: binary(),
          contact_planning_run_id: binary(),
          contact_planning_search_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_requirement_id: binary(),
          contact_requirement_version: pos_integer(),
          provider_opportunity_ref: binary(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          expires_at: DateTime.t(),
          availability: :available | :limited | :unavailable,
          estimated_capacity_document: map(),
          synthetic: boolean(),
          route_binding_document: map(),
          normalized_opportunity_document: map(),
          provider_evidence_document: map(),
          evaluation_document: map(),
          eligible: boolean(),
          content_sha256: binary(),
          captured_at: DateTime.t(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :contact_opportunity_snapshot_id,
    :contact_planning_run_id,
    :contact_planning_search_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :provider_opportunity_ref,
    :starts_at,
    :ends_at,
    :expires_at,
    :availability,
    :estimated_capacity_document,
    :synthetic,
    :route_binding_document,
    :normalized_opportunity_document,
    :provider_evidence_document,
    :evaluation_document,
    :eligible,
    :content_sha256,
    :captured_at,
    :inserted_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    snapshot =
      %__MODULE__{
        contact_opportunity_snapshot_id:
          value(attrs, :contact_opportunity_snapshot_id, Ids.new("opportunity_snapshot")),
        contact_planning_run_id: required(attrs, :contact_planning_run_id),
        contact_planning_search_id: required(attrs, :contact_planning_search_id),
        organization_id: required(attrs, :organization_id),
        mission_id: required(attrs, :mission_id),
        contact_requirement_id: required(attrs, :contact_requirement_id),
        contact_requirement_version:
          positive(value(attrs, :contact_requirement_version), :contact_requirement_version),
        provider_opportunity_ref: required(attrs, :provider_opportunity_ref),
        starts_at: datetime(value(attrs, :starts_at), :starts_at),
        ends_at: datetime(value(attrs, :ends_at), :ends_at),
        expires_at: datetime(value(attrs, :expires_at), :expires_at),
        availability: normalize_availability(value(attrs, :availability)),
        estimated_capacity_document:
          document(value(attrs, :estimated_capacity_document, %{}), :estimated_capacity_document),
        synthetic: boolean(value(attrs, :synthetic, false), :synthetic),
        route_binding_document:
          document(value(attrs, :route_binding_document), :route_binding_document),
        normalized_opportunity_document:
          document(
            value(attrs, :normalized_opportunity_document),
            :normalized_opportunity_document
          ),
        provider_evidence_document:
          document(value(attrs, :provider_evidence_document), :provider_evidence_document),
        evaluation_document: document(value(attrs, :evaluation_document), :evaluation_document),
        eligible: boolean(value(attrs, :eligible), :eligible),
        content_sha256: required(attrs, :content_sha256),
        captured_at: datetime(value(attrs, :captured_at), :captured_at),
        inserted_at: value(attrs, :inserted_at)
      }

    if DateTime.before?(snapshot.starts_at, snapshot.ends_at),
      do: snapshot,
      else: raise(ArgumentError, "opportunity ends_at must be after starts_at")
  end

  defp normalize_availability(item) when is_atom(item) do
    if item in @availability,
      do: item,
      else: raise(ArgumentError, "unsupported opportunity availability")
  end

  defp normalize_availability(item) when is_binary(item) do
    Enum.find(@availability, &(Atom.to_string(&1) == item)) ||
      raise ArgumentError, "unsupported opportunity availability"
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")

  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp document(item, _field) when is_map(item), do: item
  defp document(_item, field), do: raise(ArgumentError, "#{field} must be an object")

  defp boolean(item, _field) when is_boolean(item), do: item
  defp boolean(_item, field), do: raise(ArgumentError, "#{field} must be boolean")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
