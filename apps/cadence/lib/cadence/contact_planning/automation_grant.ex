defmodule Cadence.ContactPlanning.AutomationGrant do
  @moduledoc "Immutable administrator-approved authorization envelope for mission automation."

  alias Cadence.ContactPlanning.ContentHash
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @actions [:plan, :repair, :submit, :approve, :execute]
  @states [:active, :revoked]

  @type action :: :plan | :repair | :submit | :approve | :execute

  @type t :: %__MODULE__{
          automation_grant_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          service_identity_id: binary(),
          fleet_planning_policy_id: binary(),
          fleet_planning_policy_version: pos_integer(),
          allowed_actions: [action()],
          maximum_horizon_seconds: pos_integer(),
          maximum_contacts: pos_integer(),
          maximum_estimated_cost_micros: non_neg_integer() | nil,
          currency: binary() | nil,
          maximum_execution_concurrency: pos_integer(),
          valid_from: DateTime.t(),
          valid_until: DateTime.t(),
          lifecycle_state: :active | :revoked,
          approved_by: binary(),
          approved_at: DateTime.t(),
          approval_reason: binary(),
          content_sha256: binary(),
          revoked_by: binary() | nil,
          revoked_at: DateTime.t() | nil,
          revocation_reason: binary(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :automation_grant_id,
    :organization_id,
    :mission_id,
    :service_identity_id,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :allowed_actions,
    :maximum_horizon_seconds,
    :maximum_contacts,
    :maximum_estimated_cost_micros,
    :currency,
    :maximum_execution_concurrency,
    :valid_from,
    :valid_until,
    :lifecycle_state,
    :approved_by,
    :approved_at,
    :approval_reason,
    :content_sha256,
    :revoked_by,
    :revoked_at,
    :revocation_reason,
    :inserted_at,
    :updated_at
  ]

  @spec actions() :: [action()]
  def actions, do: @actions

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    grant =
      %__MODULE__{
        automation_grant_id: value(attrs, :automation_grant_id, Ids.new("automation_grant")),
        organization_id: required(attrs, :organization_id),
        mission_id: required(attrs, :mission_id),
        service_identity_id: required(attrs, :service_identity_id),
        fleet_planning_policy_id: required(attrs, :fleet_planning_policy_id),
        fleet_planning_policy_version:
          positive(
            value(attrs, :fleet_planning_policy_version),
            :fleet_planning_policy_version
          ),
        allowed_actions: actions(value(attrs, :allowed_actions)),
        maximum_horizon_seconds:
          positive(value(attrs, :maximum_horizon_seconds), :maximum_horizon_seconds),
        maximum_contacts: positive(value(attrs, :maximum_contacts), :maximum_contacts),
        maximum_estimated_cost_micros:
          optional_non_negative(
            value(attrs, :maximum_estimated_cost_micros),
            :maximum_estimated_cost_micros
          ),
        currency: currency(value(attrs, :currency)),
        maximum_execution_concurrency:
          positive(
            value(attrs, :maximum_execution_concurrency),
            :maximum_execution_concurrency
          ),
        valid_from: datetime(value(attrs, :valid_from), :valid_from),
        valid_until: datetime(value(attrs, :valid_until), :valid_until),
        lifecycle_state:
          attrs
          |> value(:lifecycle_state, :active)
          |> atom(@states, :lifecycle_state),
        approved_by: required(attrs, :approved_by),
        approved_at: datetime(value(attrs, :approved_at), :approved_at),
        approval_reason: required(attrs, :approval_reason),
        content_sha256: value(attrs, :content_sha256),
        revoked_by: optional_string(value(attrs, :revoked_by)),
        revoked_at: optional_datetime(value(attrs, :revoked_at), :revoked_at),
        revocation_reason: string(value(attrs, :revocation_reason, ""), :revocation_reason),
        inserted_at: value(attrs, :inserted_at),
        updated_at: value(attrs, :updated_at)
      }
      |> validate_validity()
      |> validate_cost_currency()
      |> validate_revocation_shape()

    %{grant | content_sha256: grant.content_sha256 || content_sha256(grant)}
  end

  @spec content_document(t()) :: map()
  def content_document(%__MODULE__{} = grant) do
    %{
      "organization_id" => grant.organization_id,
      "mission_id" => grant.mission_id,
      "service_identity_id" => grant.service_identity_id,
      "fleet_planning_policy_id" => grant.fleet_planning_policy_id,
      "fleet_planning_policy_version" => grant.fleet_planning_policy_version,
      "allowed_actions" => Enum.map(grant.allowed_actions, &Atom.to_string/1),
      "maximum_horizon_seconds" => grant.maximum_horizon_seconds,
      "maximum_contacts" => grant.maximum_contacts,
      "maximum_estimated_cost_micros" => grant.maximum_estimated_cost_micros,
      "currency" => grant.currency,
      "maximum_execution_concurrency" => grant.maximum_execution_concurrency,
      "valid_from" => DateTime.to_iso8601(grant.valid_from),
      "valid_until" => DateTime.to_iso8601(grant.valid_until)
    }
  end

  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{} = grant),
    do: grant |> content_document() |> JsonDocument.encode() |> ContentHash.sha256()

  defp validate_validity(grant) do
    if DateTime.before?(grant.valid_from, grant.valid_until),
      do: grant,
      else: raise(ArgumentError, "automation grant valid_until must be after valid_from")
  end

  defp validate_cost_currency(
         %__MODULE__{
           maximum_estimated_cost_micros: nil,
           currency: nil
         } = grant
       ),
       do: grant

  defp validate_cost_currency(
         %__MODULE__{
           maximum_estimated_cost_micros: cost,
           currency: currency
         } = grant
       )
       when is_integer(cost) and is_binary(currency),
       do: grant

  defp validate_cost_currency(_grant),
    do: raise(ArgumentError, "automation grant cost and currency must be set together")

  defp validate_revocation_shape(%__MODULE__{lifecycle_state: :active} = grant) do
    if is_nil(grant.revoked_by) and is_nil(grant.revoked_at) and grant.revocation_reason == "",
      do: grant,
      else: raise(ArgumentError, "active automation grant cannot have revocation evidence")
  end

  defp validate_revocation_shape(%__MODULE__{lifecycle_state: :revoked} = grant) do
    if grant.revoked_by && grant.revoked_at && grant.revocation_reason != "",
      do: grant,
      else: raise(ArgumentError, "revoked automation grant requires revocation evidence")
  end

  defp actions(items) when is_list(items) and items != [] do
    normalized =
      items
      |> Enum.map(&atom(&1, @actions, :allowed_actions))
      |> Enum.uniq()
      |> Enum.sort()

    if length(normalized) == length(items),
      do: normalized,
      else: raise(ArgumentError, "automation grant actions must be unique")
  end

  defp actions(_items), do: raise(ArgumentError, "automation grant requires allowed actions")

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp optional_non_negative(nil, _field), do: nil

  defp optional_non_negative(value, _field) when is_integer(value) and value >= 0,
    do: value

  defp optional_non_negative(_value, field),
    do: raise(ArgumentError, "#{field} must not be negative")

  defp currency(nil), do: nil
  defp currency(value) when is_binary(value) and value != "", do: String.upcase(value)
  defp currency(_value), do: raise(ArgumentError, "currency must be an ISO-style code")

  defp string(value, _field) when is_binary(value), do: value
  defp string(_value, field), do: raise(ArgumentError, "#{field} must be a string")

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: raise(ArgumentError, "optional actor must be non-empty")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(value, field), do: datetime(value, field)

  defp atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp atom(value, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
