defmodule Cadence.Management.Commanding do
  @moduledoc """
  Management-plane boundary for command authoring, request, and approval.

  Persistence remains in the domain-first Commanding context during migration;
  consumers use this boundary so Control receives only `ApprovedCommand`.
  """

  alias Cadence.Commanding, as: LegacyCommanding
  alias Cadence.Management.Commanding.ApprovedCommand

  defdelegate persist_command_stage(organization_id, command_stage), to: LegacyCommanding
  defdelegate update_command_stage(organization_id, command_stage), to: LegacyCommanding

  defdelegate fetch_command_stage(organization_id, mission_id, command_stage_id),
    to: LegacyCommanding

  defdelegate list_command_stages(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding

  defdelegate persist_staged_command_item(organization_id, staged_command_item),
    to: LegacyCommanding

  defdelegate update_staged_command_item(organization_id, staged_command_item),
    to: LegacyCommanding

  defdelegate fetch_staged_command_item(organization_id, mission_id, staged_command_item_id),
    to: LegacyCommanding

  defdelegate list_staged_command_items(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding

  defdelegate persist_command_request(organization_id, command_request), to: LegacyCommanding

  defdelegate fetch_command_request(organization_id, mission_id, command_request_id),
    to: LegacyCommanding

  defdelegate list_command_requests(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding

  defdelegate fetch_command_approval(organization_id, mission_id, command_approval_id),
    to: LegacyCommanding

  defdelegate list_command_approvals(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding

  defdelegate reject_command_request(
                organization_id,
                mission_id,
                command_request_id,
                rejected_by,
                opts \\ []
              ),
              to: LegacyCommanding

  defdelegate submit_staged_command_items(
                organization_id,
                mission_id,
                command_stage_id,
                staged_command_item_ids,
                requested_by \\ %{}
              ),
              to: LegacyCommanding

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
           LegacyCommanding.approve_command_request(
             organization_id,
             mission_id,
             command_request_id,
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
           LegacyCommanding.fetch_command_request(
             organization_id,
             mission_id,
             command_request_id
           ) do
      approved_handoff(request)
    end
  end

  defp approved_handoff(request) do
    request.organization_id
    |> LegacyCommanding.list_command_approvals(request.mission_id,
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
