defmodule Cadence.ContactPlanning.FleetPlanningPolicyVersion do
  @moduledoc "Immutable normalized content for one fleet planning policy version."

  alias Cadence.ContactPlanning.{ContentHash, FleetPlanningPolicyDocument}
  alias Cadence.Ids

  @type t :: %__MODULE__{
          fleet_planning_policy_version_id: binary(),
          fleet_planning_policy_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          version: pos_integer(),
          horizon_document: map(),
          scoring_document: map(),
          resource_policy_document: map(),
          budget_quota_document: map(),
          redundancy_document: map(),
          automation_repair_document: map(),
          content_sha256: binary(),
          created_by: binary(),
          created_at: DateTime.t()
        }

  defstruct [
    :fleet_planning_policy_version_id,
    :fleet_planning_policy_id,
    :organization_id,
    :mission_id,
    :version,
    :horizon_document,
    :scoring_document,
    :resource_policy_document,
    :budget_quota_document,
    :redundancy_document,
    :automation_repair_document,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    with {:ok, horizon} <-
           FleetPlanningPolicyDocument.normalize_horizon(value(attrs, :horizon_document, %{})),
         {:ok, scoring} <-
           FleetPlanningPolicyDocument.normalize_scoring(value(attrs, :scoring_document, %{})),
         {:ok, resources} <-
           FleetPlanningPolicyDocument.normalize_resources(
             value(attrs, :resource_policy_document, %{})
           ),
         {:ok, budgets} <-
           FleetPlanningPolicyDocument.normalize_budgets(
             value(attrs, :budget_quota_document, %{})
           ),
         {:ok, redundancy} <-
           FleetPlanningPolicyDocument.normalize_redundancy(
             value(attrs, :redundancy_document, %{})
           ),
         {:ok, automation} <-
           FleetPlanningPolicyDocument.normalize_automation(
             value(attrs, :automation_repair_document, %{})
           ) do
      version =
        %__MODULE__{
          fleet_planning_policy_version_id:
            value(
              attrs,
              :fleet_planning_policy_version_id,
              Ids.new("fleet_planning_policy_version")
            ),
          fleet_planning_policy_id: required(attrs, :fleet_planning_policy_id),
          organization_id: required(attrs, :organization_id),
          mission_id: required(attrs, :mission_id),
          version: positive(value(attrs, :version, 1), :version),
          horizon_document: horizon,
          scoring_document: scoring,
          resource_policy_document: resources,
          budget_quota_document: budgets,
          redundancy_document: redundancy,
          automation_repair_document: automation,
          content_sha256: value(attrs, :content_sha256),
          created_by: required(attrs, :created_by),
          created_at: datetime(value(attrs, :created_at, DateTime.utc_now()), :created_at)
        }

      {:ok, %{version | content_sha256: version.content_sha256 || content_sha256(version)}}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, version} -> version
      {:error, reason} -> raise ArgumentError, "invalid fleet planning policy: #{inspect(reason)}"
    end
  end

  @spec content_document(t()) :: map()
  def content_document(%__MODULE__{} = version) do
    %{
      "horizon" => version.horizon_document,
      "scoring" => version.scoring_document,
      "resources" => version.resource_policy_document,
      "budgets" => version.budget_quota_document,
      "redundancy" => version.redundancy_document,
      "automation_repair" => version.automation_repair_document
    }
  end

  @spec content_sha256(t()) :: binary()
  def content_sha256(%__MODULE__{} = version),
    do: version |> content_document() |> ContentHash.sha256()

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
