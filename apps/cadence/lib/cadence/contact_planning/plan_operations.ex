defmodule Cadence.ContactPlanning.PlanOperations do
  @moduledoc """
  #257 (director 11-19): the console's contact-plan submits and approves, one record per
  operation id, scoped to (organization, mission, operation id). Each record holds the action,
  the plan, the actor, a SHA-256 of the normalized request and the original answer (status and
  body). It is written in the same transaction as the submit or the decision, after the plan row
  lock, so a retry of the same request gets the original answer back (`replayed: true`) and
  never runs the action twice; any other request on a known operation id is refused.

  Normalized request: integers as given, the note trimmed (blank is none), acknowledgements
  sorted by requirement id with each reason trimmed.
  """

  use Ecto.Schema

  import Ecto.Query

  alias Cadence.Repo

  @primary_key {:contact_plan_operation_id, :string, autogenerate: false}
  schema "contact_plan_operations" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:operation_id, :string)
    field(:contact_plan_id, :string)
    field(:action, :string)
    field(:actor_id, :string)
    field(:request_sha256, :string)
    field(:response_status, :integer)
    field(:response_document, :map)
    field(:inserted_at, :utc_datetime_usec)
  end

  @type action :: :submit | :approve
  @type request :: %{
          required(:expected_version) => pos_integer(),
          optional(:note) => binary() | nil,
          optional(:acknowledgements) => [map()]
        }
  @type answer :: {pos_integer(), map()}

  @doc """
  What a known operation id means for this request: `:new` (unknown id), `{:replay, answer}`
  (same action, plan, actor and request), `:duplicate_operation` (the same plan, anything else
  different) or `:operation_conflict` (the id belongs to another plan). Call it inside the
  action's transaction, after the plan row lock.
  """
  @spec check(binary(), binary(), binary(), binary(), action(), binary(), request()) ::
          :new | {:replay, answer()} | :duplicate_operation | :operation_conflict
  def check(organization_id, mission_id, operation_id, plan_id, action, actor_id, request) do
    case fetch(organization_id, mission_id, operation_id) do
      nil -> :new
      record -> compare(record, plan_id, action, actor_id, digest(action, request))
    end
  end

  @doc """
  Records the operation and its answer. A unique-index race (another request claimed the id
  first) answers what `check/7` would now say, so the caller never sees a 500.
  """
  @spec record(map(), answer()) :: :ok | {:error, :duplicate_operation | :operation_conflict}
  def record(attrs, {status, body}) do
    row = %{
      contact_plan_operation_id: Cadence.Ids.new("contact_plan_operation"),
      organization_id: attrs.organization_id,
      mission_id: attrs.mission_id,
      operation_id: attrs.operation_id,
      contact_plan_id: attrs.contact_plan_id,
      action: Atom.to_string(attrs.action),
      actor_id: attrs.actor_id,
      request_sha256: digest(attrs.action, attrs.request),
      response_status: status,
      response_document: body,
      inserted_at: DateTime.utc_now()
    }

    # ON CONFLICT DO NOTHING, not a constraint error: a failed insert would abort the caller's
    # transaction, and the race must be answered from inside it.
    case Repo.insert_all(__MODULE__, [row],
           on_conflict: :nothing,
           conflict_target: [:organization_id, :mission_id, :operation_id]
         ) do
      {1, _rows} -> :ok
      {0, _rows} -> {:error, raced(attrs)}
    end
  end

  @doc "The normalized request's digest (see the moduledoc)."
  @spec digest(action(), request()) :: binary()
  def digest(action, request) do
    acknowledgements =
      (request[:acknowledgements] || [])
      |> Enum.map(&%{"requirement_id" => &1.requirement_id, "reason" => trim(&1.reason)})
      |> Enum.sort_by(& &1["requirement_id"])

    [Atom.to_string(action), request.expected_version, trim(request[:note]), acknowledgements]
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp compare(%{contact_plan_id: plan_id} = record, plan_id, action, actor_id, sha) do
    if record.action == Atom.to_string(action) and record.actor_id == actor_id and
         record.request_sha256 == sha,
       do: {:replay, {record.response_status, record.response_document}},
       else: :duplicate_operation
  end

  defp compare(_record, _plan_id, _action, _actor_id, _sha), do: :operation_conflict

  defp raced(attrs) do
    case fetch(attrs.organization_id, attrs.mission_id, attrs.operation_id) do
      %{contact_plan_id: plan_id} when plan_id == attrs.contact_plan_id -> :duplicate_operation
      _other -> :operation_conflict
    end
  end

  defp fetch(organization_id, mission_id, operation_id) do
    __MODULE__
    |> where(
      [o],
      o.organization_id == ^organization_id and o.mission_id == ^mission_id and
        o.operation_id == ^operation_id
    )
    |> Repo.one()
  end

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim(_value), do: nil
end
