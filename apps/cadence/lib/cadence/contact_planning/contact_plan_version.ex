defmodule Cadence.ContactPlanning.ContactPlanVersion do
  @moduledoc "Immutable review and commitment manifest for one Contact Plan version."

  alias Cadence.ContactPlanning.ContentHash
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type t :: %__MODULE__{
          contact_plan_version_id: binary(),
          contact_plan_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          version: pos_integer(),
          requirement_refs_document: map(),
          planning_run_refs_document: map(),
          selected_snapshot_ids: [binary()],
          locked_snapshot_ids: [binary()],
          rejected_snapshot_ids: [binary()],
          coverage_document: map(),
          conflict_document: map(),
          unsatisfied_document: map(),
          policy_snapshot_document: map(),
          rationale: binary(),
          content_sha256: binary(),
          created_by: binary(),
          created_at: DateTime.t()
        }

  defstruct [
    :contact_plan_version_id,
    :contact_plan_id,
    :organization_id,
    :mission_id,
    :version,
    :requirement_refs_document,
    :planning_run_refs_document,
    :selected_snapshot_ids,
    :locked_snapshot_ids,
    :rejected_snapshot_ids,
    :coverage_document,
    :conflict_document,
    :unsatisfied_document,
    :policy_snapshot_document,
    :rationale,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{} =
      version =
      %__MODULE__{
        contact_plan_version_id:
          value(attrs, :contact_plan_version_id, Ids.new("contact_plan_version")),
        contact_plan_id: required(attrs, :contact_plan_id),
        organization_id: required(attrs, :organization_id),
        mission_id: required(attrs, :mission_id),
        version: positive(value(attrs, :version, 1), :version),
        requirement_refs_document:
          document(value(attrs, :requirement_refs_document), :requirement_refs_document),
        planning_run_refs_document:
          document(value(attrs, :planning_run_refs_document), :planning_run_refs_document),
        selected_snapshot_ids:
          string_list(value(attrs, :selected_snapshot_ids, []), :selected_snapshot_ids),
        locked_snapshot_ids:
          string_list(value(attrs, :locked_snapshot_ids, []), :locked_snapshot_ids),
        rejected_snapshot_ids:
          string_list(value(attrs, :rejected_snapshot_ids, []), :rejected_snapshot_ids),
        coverage_document: document(value(attrs, :coverage_document), :coverage_document),
        conflict_document: document(value(attrs, :conflict_document), :conflict_document),
        unsatisfied_document:
          document(value(attrs, :unsatisfied_document), :unsatisfied_document),
        policy_snapshot_document:
          document(value(attrs, :policy_snapshot_document), :policy_snapshot_document),
        rationale: string(value(attrs, :rationale, ""), :rationale),
        content_sha256: value(attrs, :content_sha256),
        created_by: required(attrs, :created_by),
        created_at: datetime(value(attrs, :created_at, DateTime.utc_now()), :created_at)
      }
      |> validate_snapshot_sets()

    %__MODULE__{
      version
      | content_sha256: version.content_sha256 || ContentHash.sha256(content_document(version))
    }
  end

  @spec content_document(t()) :: map()
  def content_document(%__MODULE__{} = version) do
    %{
      "requirements" => version.requirement_refs_document,
      "planning_runs" => version.planning_run_refs_document,
      "selected_snapshot_ids" => version.selected_snapshot_ids,
      "locked_snapshot_ids" => version.locked_snapshot_ids,
      "rejected_snapshot_ids" => version.rejected_snapshot_ids,
      "coverage" => version.coverage_document,
      "conflicts" => version.conflict_document,
      "unsatisfied" => version.unsatisfied_document,
      "policy" => version.policy_snapshot_document,
      "rationale" => version.rationale
    }
  end

  defp validate_snapshot_sets(version) do
    selected = MapSet.new(version.selected_snapshot_ids)
    locked = MapSet.new(version.locked_snapshot_ids)
    rejected = MapSet.new(version.rejected_snapshot_ids)

    cond do
      MapSet.size(selected) != length(version.selected_snapshot_ids) ->
        raise ArgumentError, "selected snapshots contain duplicates"

      MapSet.size(rejected) != length(version.rejected_snapshot_ids) ->
        raise ArgumentError, "rejected snapshots contain duplicates"

      MapSet.size(locked) != length(version.locked_snapshot_ids) ->
        raise ArgumentError, "locked snapshots contain duplicates"

      not MapSet.disjoint?(selected, locked) or
        not MapSet.disjoint?(selected, rejected) or
          not MapSet.disjoint?(locked, rejected) ->
        raise ArgumentError, "snapshot dispositions must be disjoint"

      true ->
        version
    end
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp string(item, _field) when is_binary(item), do: item
  defp string(_item, field), do: raise(ArgumentError, "#{field} must be a string")

  defp string_list(items, _field) when is_list(items) do
    if Enum.all?(items, &(is_binary(&1) and &1 != "")),
      do: items,
      else: raise(ArgumentError, "snapshot references must be strings")
  end

  defp string_list(_items, field), do: raise(ArgumentError, "#{field} must be a list")
  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")
  defp document(item, _field) when is_map(item), do: JsonDocument.encode(item)
  defp document(_item, field), do: raise(ArgumentError, "#{field} must be an object")
  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
