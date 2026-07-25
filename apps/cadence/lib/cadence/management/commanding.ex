defmodule Cadence.Management.Commanding do
  @moduledoc """
  Management-plane boundary for command authoring, request, and approval.

  Command stages, requests, and approvals remain management-owned. Control
  receives only the immutable `ApprovedCommand` handoff.
  """

  alias Cadence.Commanding.{
    CommandApproval,
    CommandRequest,
    CommandStage,
    RequestStore,
    StagedCommandItem,
    StageStore
  }

  alias Cadence.Management.Commanding.ApprovedCommand

  @spec persist_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  defdelegate persist_command_stage(organization_id, command_stage),
    to: StageStore,
    as: :persist_stage

  @spec update_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  defdelegate update_command_stage(organization_id, command_stage),
    to: StageStore,
    as: :update_stage

  @spec fetch_command_stage(binary(), binary(), binary()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  defdelegate fetch_command_stage(organization_id, mission_id, command_stage_id),
    to: StageStore,
    as: :fetch_stage

  @spec list_command_stages(binary(), binary(), keyword()) :: [CommandStage.t()]
  defdelegate list_command_stages(organization_id, mission_id, opts \\ []),
    to: StageStore,
    as: :list_stages

  @spec persist_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  defdelegate persist_staged_command_item(organization_id, staged_command_item),
    to: StageStore,
    as: :persist_item

  @spec update_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  defdelegate update_staged_command_item(organization_id, staged_command_item),
    to: StageStore,
    as: :update_item

  @spec fetch_staged_command_item(binary(), binary(), binary()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  defdelegate fetch_staged_command_item(organization_id, mission_id, staged_command_item_id),
    to: StageStore,
    as: :fetch_item

  @spec list_staged_command_items(binary(), binary(), keyword()) :: [StagedCommandItem.t()]
  defdelegate list_staged_command_items(organization_id, mission_id, opts \\ []),
    to: StageStore,
    as: :list_items

  @spec persist_command_request(binary(), CommandRequest.t()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  defdelegate persist_command_request(organization_id, command_request),
    to: RequestStore,
    as: :persist_request

  @spec fetch_command_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  defdelegate fetch_command_request(organization_id, mission_id, command_request_id),
    to: RequestStore,
    as: :fetch_request

  @spec list_command_requests(binary(), binary(), keyword()) :: [CommandRequest.t()]
  defdelegate list_command_requests(organization_id, mission_id, opts \\ []),
    to: RequestStore,
    as: :list_requests

  @spec fetch_command_approval(binary(), binary(), binary()) ::
          {:ok, CommandApproval.t()} | {:error, term()}
  defdelegate fetch_command_approval(organization_id, mission_id, command_approval_id),
    to: RequestStore,
    as: :fetch_approval

  @spec list_command_approvals(binary(), binary(), keyword()) :: [CommandApproval.t()]
  defdelegate list_command_approvals(organization_id, mission_id, opts \\ []),
    to: RequestStore,
    as: :list_approvals

  @spec reject_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{approval: CommandApproval.t(), command_request: CommandRequest.t()}}
          | {:error, term()}
  def reject_command_request(
        organization_id,
        mission_id,
        command_request_id,
        rejected_by,
        opts \\ []
      ) do
    RequestStore.decide_request(
      organization_id,
      mission_id,
      command_request_id,
      :rejected,
      rejected_by,
      opts
    )
  end

  @spec submit_staged_command_items(binary(), binary(), binary(), [binary()], map()) ::
          {:ok, [CommandRequest.t()]} | {:error, term()}
  def submit_staged_command_items(
        organization_id,
        mission_id,
        command_stage_id,
        staged_command_item_ids,
        requested_by \\ %{}
      ) do
    StageStore.submit_items(
      organization_id,
      mission_id,
      command_stage_id,
      staged_command_item_ids,
      requested_by
    )
  end

  @spec approve_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def approve_command_request(
        organization_id,
        mission_id,
        command_request_id,
        approved_by,
        opts \\ []
      ) do
    with {:ok, %{command_request: request, approval: approval} = result} <-
           RequestStore.decide_request(
             organization_id,
             mission_id,
             command_request_id,
             :approved,
             approved_by,
             opts
           ),
         {:ok, %ApprovedCommand{} = approved_command} <- ApprovedCommand.new(request, approval) do
      {:ok, Map.put(result, :approved_command, approved_command)}
    end
  end

  @spec fetch_approved_command(binary(), binary(), binary()) ::
          {:ok, ApprovedCommand.t()} | {:error, term()}
  def fetch_approved_command(organization_id, mission_id, command_request_id) do
    with {:ok, request} <-
           RequestStore.fetch_request(
             organization_id,
             mission_id,
             command_request_id
           ) do
      approved_handoff(request)
    end
  end

  defp approved_handoff(request) do
    request.organization_id
    |> RequestStore.list_approvals(request.mission_id,
      command_request_id: request.command_request_id,
      decision: :approved
    )
    |> List.last()
    |> case do
      nil -> ApprovedCommand.from_automatic_policy(request)
      approval -> ApprovedCommand.new(%{request | lifecycle_state: :approved}, approval)
    end
  end
end
