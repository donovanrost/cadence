defmodule CadenceWeb.OpsFleetPolicyRecovery do
  @moduledoc "Latest policy command and receipt, retained across page and transport lifetimes."
  use Ecto.Schema
  import Ecto.Query
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Applications.OpsConsole.Actions.FleetPolicyWorkflow, as: Workflow
  alias Cadence.Auth.Scope
  alias Cadence.Repo

  @primary_key false
  @identity [:organization_id, :user_id, :mission_id]
  schema "ops_fleet_policy_recoveries" do
    field(:organization_id, :string, primary_key: true)
    field(:user_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:sequence, :integer, default: 0)
    field(:operation, :map)
    timestamps(type: :utc_datetime_usec)
  end

  # Callers reauthorize the policy placement before reading or reserving a command.
  def read(%Scope{} = scope, mission) do
    case Repo.one(query(scope, mission)) do
      nil -> %{sequence: 0, operation: nil}
      row -> %{sequence: row.sequence, operation: row.operation}
    end
  end

  def reserve(%Scope{} = scope, mission, operation) do
    {:ok, safe} = JSONBoundary.safe(operation)

    Repo.transaction(fn ->
      Repo.insert!(
        %__MODULE__{
          organization_id: scope.organization_id,
          user_id: scope.user.user_id,
          mission_id: mission
        },
        on_conflict: :nothing,
        conflict_target: @identity
      )

      row = Repo.one!(from(r in query(scope, mission), lock: "FOR UPDATE"))

      if operation.sequence == row.sequence + 1 and
           not unresolved_effect?(row.operation) do
        row
        |> Ecto.Changeset.change(sequence: operation.sequence, operation: safe)
        |> Repo.update!()

        :reserved
      else
        Repo.rollback(:rejected)
      end
    end)
  end

  def complete(%Scope{} = scope, mission, operation) do
    {:ok, safe} = JSONBoundary.safe(operation)

    Repo.transaction(fn ->
      row = Repo.one!(from(r in query(scope, mission), lock: "FOR UPDATE"))
      previous = row.operation

      if row.sequence == operation.sequence and previous["status"] == "unconfirmed" and
           previous["action"] == safe["action"] and previous["input"] == safe["input"] do
        row |> Ecto.Changeset.change(operation: safe) |> Repo.update!()
        operation
      else
        Repo.rollback(:changed_operation)
      end
    end)
  end

  defp unresolved_effect?(%{"status" => "unconfirmed", "action" => action}),
    do: not Workflow.validation?(action)

  defp unresolved_effect?(_), do: false

  defp query(%Scope{} = scope, mission) do
    from(r in __MODULE__,
      where:
        r.organization_id == ^scope.organization_id and r.user_id == ^scope.user.user_id and
          r.mission_id == ^mission
    )
  end
end
