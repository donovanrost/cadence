defmodule Cadence.Control.PlanningOperations do
  @moduledoc """
  Idempotent creates for contact requirements and templates (lead, after qa's P4 duplicates): an
  optional client `operation_id`, the same contract as command groups. The new row's id is derived
  from the mission and the operation id, so a replay finds the row it already made and answers
  `{:duplicate_operation, id}` instead of creating a second one. No new storage: the id is the key.
  """

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates}

  @type create :: (binary() | nil -> {:ok, term()} | {:error, term()})

  @prefixes %{
    requirement: "contact_requirement_op_",
    template: "contact_requirement_template_op_"
  }

  @doc """
  Runs `create.(id)` once per `operation_id`. `nil` creates without one (`create.(nil)`).
  """
  @spec create_once(Scope.t(), binary(), :requirement | :template, term(), create()) ::
          {:ok, term()} | {:error, term()}
  def create_once(_scope, _mission_id, _kind, nil, create), do: create.(nil)

  def create_once(%Scope{} = scope, mission_id, kind, operation_id, create)
      when is_binary(operation_id) and byte_size(operation_id) in 1..200 do
    org = scope.organization_id
    id = derived_id(kind, org, mission_id, operation_id)

    if exists?(kind, org, mission_id, id),
      do: duplicate(id),
      else: create_new(kind, org, mission_id, id, create)
  end

  def create_once(_scope, _mission_id, _kind, _operation_id, _create),
    do: {:error, {:invalid_params, %{operation_id: "must be text, 1 to 200 characters"}}}

  # A failed insert whose id now exists lost a race to a concurrent replay.
  defp create_new(kind, org, mission_id, id, create) do
    case create.(id) do
      {:ok, _created} = ok ->
        ok

      {:error, reason} ->
        if exists?(kind, org, mission_id, id), do: duplicate(id), else: {:error, reason}
    end
  end

  @doc "The id a create with this operation id gets."
  @spec derived_id(:requirement | :template, binary(), binary(), binary()) :: binary()
  def derived_id(kind, organization_id, mission_id, operation_id) do
    digest =
      :crypto.hash(:sha256, Enum.join([organization_id, mission_id, operation_id], <<0>>))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 32)

    Map.fetch!(@prefixes, kind) <> digest
  end

  defp duplicate(id), do: {:error, {:duplicate_operation, id}}

  defp exists?(:requirement, org, mission, id),
    do: match?({:ok, _requirement, _version}, ContactRequirements.fetch(org, mission, id))

  defp exists?(:template, org, mission, id),
    do: match?({:ok, _template, _version}, ContactRequirementTemplates.fetch(org, mission, id))
end
