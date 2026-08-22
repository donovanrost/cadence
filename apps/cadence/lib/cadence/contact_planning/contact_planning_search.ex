defmodule Cadence.ContactPlanning.ContactPlanningSearch do
  @moduledoc "Durable outcome for one exact provider route considered by a planning run."

  alias Cadence.Ids

  @outcomes [
    :succeeded_with_results,
    :succeeded_without_results,
    :not_ready,
    :excluded_by_requirement,
    :failed
  ]

  @type outcome ::
          :succeeded_with_results
          | :succeeded_without_results
          | :not_ready
          | :excluded_by_requirement
          | :failed

  @type t :: %__MODULE__{
          contact_planning_search_id: binary(),
          contact_planning_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          route_key: binary(),
          route_order: non_neg_integer(),
          provider_id: binary() | nil,
          provider_version: pos_integer() | nil,
          provider_account_id: binary() | nil,
          provider_account_version: pos_integer() | nil,
          provider_account_grant_id: binary() | nil,
          provider_account_grant_version: pos_integer() | nil,
          provider_display_name: binary() | nil,
          outcome: outcome(),
          opportunity_count: non_neg_integer(),
          route_binding_document: map(),
          readiness_document: map(),
          error_document: map(),
          content_sha256: binary(),
          started_at: DateTime.t(),
          completed_at: DateTime.t(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :contact_planning_search_id,
    :contact_planning_run_id,
    :organization_id,
    :mission_id,
    :route_key,
    :route_order,
    :provider_id,
    :provider_version,
    :provider_account_id,
    :provider_account_version,
    :provider_account_grant_id,
    :provider_account_grant_version,
    :provider_display_name,
    :outcome,
    :opportunity_count,
    :route_binding_document,
    :readiness_document,
    :error_document,
    :content_sha256,
    :started_at,
    :completed_at,
    :inserted_at
  ]

  @spec outcomes() :: [outcome()]
  def outcomes, do: @outcomes

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      contact_planning_search_id:
        value(attrs, :contact_planning_search_id, Ids.new("planning_search")),
      contact_planning_run_id: required(attrs, :contact_planning_run_id),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      route_key: required(attrs, :route_key),
      route_order: non_negative(value(attrs, :route_order, 0), :route_order),
      provider_id: optional_string(value(attrs, :provider_id), :provider_id),
      provider_version: optional_positive(value(attrs, :provider_version), :provider_version),
      provider_account_id:
        optional_string(value(attrs, :provider_account_id), :provider_account_id),
      provider_account_version:
        optional_positive(
          value(attrs, :provider_account_version),
          :provider_account_version
        ),
      provider_account_grant_id:
        optional_string(value(attrs, :provider_account_grant_id), :provider_account_grant_id),
      provider_account_grant_version:
        optional_positive(
          value(attrs, :provider_account_grant_version),
          :provider_account_grant_version
        ),
      provider_display_name:
        optional_string(value(attrs, :provider_display_name), :provider_display_name),
      outcome: normalize_outcome(value(attrs, :outcome)),
      opportunity_count: non_negative(value(attrs, :opportunity_count, 0), :opportunity_count),
      route_binding_document:
        document(value(attrs, :route_binding_document, %{}), :route_binding_document),
      readiness_document: document(value(attrs, :readiness_document, %{}), :readiness_document),
      error_document: document(value(attrs, :error_document, %{}), :error_document),
      content_sha256: required(attrs, :content_sha256),
      started_at: datetime(value(attrs, :started_at), :started_at),
      completed_at: datetime(value(attrs, :completed_at), :completed_at),
      inserted_at: value(attrs, :inserted_at)
    }
  end

  defp normalize_outcome(item) when is_atom(item) do
    if item in @outcomes,
      do: item,
      else: raise(ArgumentError, "unsupported planning search outcome")
  end

  defp normalize_outcome(item) when is_binary(item) do
    Enum.find(@outcomes, &(Atom.to_string(&1) == item)) ||
      raise(ArgumentError, "unsupported planning search outcome")
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil, _field), do: nil
  defp optional_string(item, _field) when is_binary(item) and item != "", do: item
  defp optional_string(_item, field), do: raise(ArgumentError, "#{field} must be a string")

  defp optional_positive(nil, _field), do: nil
  defp optional_positive(item, field), do: positive(item, field)
  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")

  defp non_negative(item, _field) when is_integer(item) and item >= 0, do: item
  defp non_negative(_item, field), do: raise(ArgumentError, "#{field} must not be negative")

  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp document(item, _field) when is_map(item), do: item
  defp document(_item, field), do: raise(ArgumentError, "#{field} must be an object")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
