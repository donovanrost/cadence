defmodule Cadence.Commanding.RequestStore do
  @moduledoc """
  Management-owned persistence boundary for command requests and approval
  decisions.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Commanding.{
    CommandApproval,
    CommandApprovalRow,
    CommandRequest,
    CommandRequestRow,
    LifecyclePolicy,
    RequestValidation
  }

  alias Cadence.Repo

  @spec persist_request(binary(), CommandRequest.t()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def persist_request(organization_id, %CommandRequest{} = command_request)
      when is_binary(organization_id) do
    with {:ok, scoped_request} <- put_organization_scope(command_request, organization_id),
         {:ok, validated_request} <- RequestValidation.validate_and_enrich(scoped_request),
         {:ok, %CommandRequestRow{} = row} <-
           Repo.insert(CommandRequestRow.changeset(validated_request),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_request_id]
           ) do
      {:ok, CommandRequestRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def fetch_request(organization_id, mission_id, command_request_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_request_id) do
    with {:ok, %CommandRequestRow{} = row} <-
           fetch_request_row(organization_id, mission_id, command_request_id) do
      {:ok, CommandRequestRow.to_domain(row)}
    end
  end

  @spec list_requests(binary(), binary(), keyword()) :: [CommandRequest.t()]
  def list_requests(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandRequestRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:source_command_stage_id, Keyword.get(opts, :command_stage_id))
    |> maybe_filter_equals(:lifecycle_state, normalized_filter(opts, :lifecycle_state))
    |> order_by([row], asc: row.requested_at, asc: row.command_request_id)
    |> Repo.all()
    |> Enum.map(&CommandRequestRow.to_domain/1)
  end

  @spec decide_request(binary(), binary(), binary(), :approved | :rejected, map(), keyword()) ::
          {:ok, %{approval: CommandApproval.t(), command_request: CommandRequest.t()}}
          | {:error, term()}
  def decide_request(
        organization_id,
        mission_id,
        command_request_id,
        decision,
        decided_by,
        opts
      )
      when decision in [:approved, :rejected] do
    with {:ok, %CommandRequestRow{} = request_row} <-
           fetch_request_row(organization_id, mission_id, command_request_id),
         :ok <- LifecyclePolicy.ensure_request_pending_approval(request_row),
         :ok <- LifecyclePolicy.ensure_human_approval_actor(decided_by, command_request_id),
         :ok <- LifecyclePolicy.ensure_not_self_approval(request_row, decided_by) do
      approval =
        CommandApproval.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          command_request_id: command_request_id,
          decision: decision,
          decided_by: decided_by,
          decided_at: Keyword.get(opts, :decided_at, DateTime.utc_now()),
          reason: Keyword.get(opts, :reason),
          metadata: Keyword.get(opts, :metadata, %{})
        })

      request_lifecycle_state =
        case decision do
          :approved -> :approved
          :rejected -> :rejected
        end

      multi =
        Multi.new()
        |> Multi.insert(:approval, CommandApprovalRow.changeset(approval))
        |> Multi.update(
          :command_request,
          CommandRequestRow.lifecycle_changeset(request_row, request_lifecycle_state)
        )

      case Repo.transaction(multi) do
        {:ok, %{approval: approval_row, command_request: updated_request_row}} ->
          {:ok,
           %{
             approval: CommandApprovalRow.to_domain(approval_row),
             command_request: CommandRequestRow.to_domain(updated_request_row)
           }}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_approval(binary(), binary(), binary()) ::
          {:ok, CommandApproval.t()} | {:error, term()}
  def fetch_approval(organization_id, mission_id, command_approval_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_approval_id) do
    case Repo.get_by(CommandApprovalRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_approval_id: command_approval_id
         ) do
      nil -> {:error, :command_approval_not_found}
      %CommandApprovalRow{} = row -> {:ok, CommandApprovalRow.to_domain(row)}
    end
  end

  @spec list_approvals(binary(), binary(), keyword()) :: [CommandApproval.t()]
  def list_approvals(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandApprovalRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:decision, normalized_filter(opts, :decision))
    |> order_by([row], asc: row.decided_at, asc: row.command_approval_id)
    |> Repo.all()
    |> Enum.map(&CommandApprovalRow.to_domain/1)
  end

  @doc false
  @spec fetch_request_row(binary(), binary(), binary()) :: {:ok, struct()} | {:error, term()}
  def fetch_request_row(organization_id, mission_id, command_request_id) do
    case Repo.get_by(CommandRequestRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_request_id: command_request_id
         ) do
      nil -> {:error, :command_request_not_found}
      %CommandRequestRow{} = row -> {:ok, row}
    end
  end

  defp normalized_filter(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp put_organization_scope(%CommandRequest{} = command_request, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_request.organization_id do
      nil ->
        {:ok, %CommandRequest{command_request | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_request}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_request.mission_id}}
    end
  end
end
