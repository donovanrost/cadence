defmodule Cadence.ContactPlanning.GrantOperations do
  @moduledoc """
  #283 (ux U105): the console's approve, reject and narrow of an automation grant, one record
  per operation id, scoped to (organization, mission, operation id), as contact plans do (#257,
  `PlanOperations`). Written in the same transaction as the act, after the grant row lock: the
  same request again gets the original answer back (`replayed: true`) and never acts twice; any
  other request on a known operation id is refused.

  Normalized request, by action: approve, the hash approved; reject, the reason trimmed; narrow,
  the changes as sorted `[field, value]` pairs. The digest is a SHA-256 of a canonical JSON list
  (fixed positions, no maps); a golden test pins it (DECISIONS #108: a stored hash that is
  recomputed).
  """

  use Ecto.Schema

  import Ecto.Query

  alias Cadence.Auth.Scope
  alias Cadence.Repo

  @primary_key {:automation_grant_operation_id, :string, autogenerate: false}
  schema "automation_grant_operations" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:operation_id, :string)
    field(:automation_grant_id, :string)
    field(:action, :string)
    field(:actor_id, :string)
    field(:request_sha256, :string)
    field(:response_status, :integer)
    field(:response_document, :map)
    field(:inserted_at, :utc_datetime_usec)
  end

  @type action :: :approve | :reject | :narrow | :resume
  @type answer :: {pos_integer(), map()}

  @doc """
  `:new`, `{:replay, answer}` (same action, grant, actor and request), `:duplicate_operation`
  (the same grant, anything else different) or `:operation_conflict` (another grant's id).
  """
  @spec check(Scope.t(), binary(), binary(), binary(), action(), term()) ::
          :new | {:replay, answer()} | :duplicate_operation | :operation_conflict
  def check(%Scope{} = scope, mission_id, operation_id, grant_id, action, request) do
    case fetch(scope.organization_id, mission_id, operation_id) do
      nil -> :new
      record -> compare(record, grant_id, action, actor_id(scope), digest(action, request))
    end
  end

  @doc "Records the operation and its answer; a unique-index race answers as `check/6` would."
  @spec record(Scope.t(), binary(), binary(), binary(), action(), term(), answer()) ::
          :ok | {:error, :duplicate_operation | :operation_conflict}
  def record(
        %Scope{} = scope,
        mission_id,
        operation_id,
        grant_id,
        action,
        request,
        {status, body}
      ) do
    row = %{
      automation_grant_operation_id: Cadence.Ids.new("automation_grant_operation"),
      organization_id: scope.organization_id,
      mission_id: mission_id,
      operation_id: operation_id,
      automation_grant_id: grant_id,
      action: Atom.to_string(action),
      actor_id: actor_id(scope),
      request_sha256: digest(action, request),
      response_status: status,
      response_document: body,
      inserted_at: DateTime.utc_now()
    }

    case Repo.insert_all(__MODULE__, [row],
           on_conflict: :nothing,
           conflict_target: [:organization_id, :mission_id, :operation_id]
         ) do
      {1, _rows} ->
        :ok

      {0, _rows} ->
        case fetch(scope.organization_id, mission_id, operation_id) do
          %{automation_grant_id: ^grant_id} -> {:error, :duplicate_operation}
          _other -> {:error, :operation_conflict}
        end
    end
  end

  @doc "The normalized request's digest (see the moduledoc)."
  @spec digest(action(), term()) :: binary()
  def digest(action, request) do
    [1, Atom.to_string(action), normalize(action, request)]
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize(:approve, digest), do: digest
  # #499: resume is an approval-like act on the hash the approver read.
  defp normalize(:resume, digest), do: digest
  defp normalize(:reject, reason) when is_binary(reason), do: String.trim(reason)
  defp normalize(:reject, _reason), do: nil

  defp normalize(:narrow, changes) when is_map(changes) do
    changes
    |> Enum.map(fn {field, value} -> [to_string(field), value(value)] end)
    |> Enum.sort()
  end

  defp normalize(:narrow, _changes), do: []

  defp value(list) when is_list(list), do: list |> Enum.map(&to_string/1) |> Enum.sort()

  defp value(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom),
    do: Atom.to_string(atom)

  defp value(other), do: other

  defp compare(%{automation_grant_id: grant_id} = record, grant_id, action, actor_id, sha) do
    if record.action == Atom.to_string(action) and record.actor_id == actor_id and
         record.request_sha256 == sha,
       do: {:replay, {record.response_status, record.response_document}},
       else: :duplicate_operation
  end

  defp compare(_record, _grant_id, _action, _actor_id, _sha), do: :operation_conflict

  # Grant acts are person-only, so the operation's actor is the person (#283).
  defp actor_id(%Scope{user: %{user_id: id}}) when is_binary(id), do: id
  defp actor_id(_scope), do: ""

  defp fetch(organization_id, mission_id, operation_id) do
    __MODULE__
    |> where(
      [o],
      o.organization_id == ^organization_id and o.mission_id == ^mission_id and
        o.operation_id == ^operation_id
    )
    |> Repo.one()
  end
end
