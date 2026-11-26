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

  alias Cadence.Management.Commanding.ReviewAccess

  @doc "`command.request` / `command.approve` from the enforcing review policy (DECISIONS #38)."
  @spec capabilities(Cadence.Auth.Scope.t()) :: [binary()]
  defdelegate capabilities(scope), to: ReviewAccess

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
end
