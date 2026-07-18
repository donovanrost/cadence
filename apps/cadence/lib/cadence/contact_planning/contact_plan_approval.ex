defmodule Cadence.ContactPlanning.ContactPlanApproval do
  @moduledoc "Append-only named actor decision on one exact Contact Plan version."

  alias Cadence.Ids

  @decisions [:approved, :rejected]

  @type t :: %__MODULE__{
          contact_plan_approval_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_plan_id: binary(),
          contact_plan_version: pos_integer(),
          decision: :approved | :rejected,
          content_sha256: binary(),
          reason: binary(),
          actor_kind: :user | :service,
          actor_id: binary(),
          actor_document: map(),
          automation_grant_id: binary() | nil,
          automation_grant_content_sha256: binary() | nil,
          decided_at: DateTime.t(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :contact_plan_approval_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :decision,
    :content_sha256,
    :reason,
    :actor_kind,
    :actor_id,
    :actor_document,
    :automation_grant_id,
    :automation_grant_content_sha256,
    :decided_at,
    :inserted_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      contact_plan_approval_id:
        value(attrs, :contact_plan_approval_id, Ids.new("contact_plan_approval")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      contact_plan_id: required(attrs, :contact_plan_id),
      contact_plan_version: positive(value(attrs, :contact_plan_version), :contact_plan_version),
      decision: normalize_decision(value(attrs, :decision)),
      content_sha256: required(attrs, :content_sha256),
      reason: required(attrs, :reason),
      actor_kind: normalize_actor_kind(value(attrs, :actor_kind, :user)),
      actor_id: required(attrs, :actor_id),
      actor_document: document(value(attrs, :actor_document), :actor_document),
      automation_grant_id: optional_string(value(attrs, :automation_grant_id)),
      automation_grant_content_sha256:
        optional_string(value(attrs, :automation_grant_content_sha256)),
      decided_at: datetime(value(attrs, :decided_at, DateTime.utc_now()), :decided_at),
      inserted_at: value(attrs, :inserted_at)
    }
    |> validate_automation_shape()
  end

  defp normalize_decision(item) when is_atom(item) do
    if item in @decisions, do: item, else: raise(ArgumentError, "unsupported Plan decision")
  end

  defp normalize_decision(item) when is_binary(item) do
    Enum.find(@decisions, &(Atom.to_string(&1) == item)) ||
      raise ArgumentError, "unsupported Plan decision"
  end

  defp normalize_actor_kind(item) when item in [:user, :service], do: item
  defp normalize_actor_kind("user"), do: :user
  defp normalize_actor_kind("service"), do: :service
  defp normalize_actor_kind(_item), do: raise(ArgumentError, "unsupported Plan approval actor")

  defp validate_automation_shape(%__MODULE__{actor_kind: :user} = approval) do
    if is_nil(approval.automation_grant_id) and
         is_nil(approval.automation_grant_content_sha256),
       do: approval,
       else: raise(ArgumentError, "user Plan approval cannot reference an automation grant")
  end

  defp validate_automation_shape(%__MODULE__{actor_kind: :service} = approval) do
    if approval.automation_grant_id && approval.automation_grant_content_sha256,
      do: approval,
      else: raise(ArgumentError, "service Plan approval requires an exact automation grant")
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(item) when is_binary(item) and item != "", do: item
  defp optional_string(_item), do: raise(ArgumentError, "optional reference must be non-empty")

  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")
  defp document(item, _field) when is_map(item), do: item
  defp document(_item, field), do: raise(ArgumentError, "#{field} must be an object")
  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
