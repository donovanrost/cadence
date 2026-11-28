defmodule Cadence.Management.Commanding do
  @moduledoc """
  Management-plane boundary for command authoring, request, and approval.

  Command requests and approvals remain management-owned. Control receives only the immutable
  `ApprovedCommand` handoff.
  """

  alias Cadence.Commanding.{
    CommandRequest,
    RequestStore
  }

  alias Cadence.Management.Commanding.ReviewAccess

  @doc "`command.request` / `command.approve` from the enforcing review policy (DECISIONS #38)."
  @spec capabilities(Cadence.Auth.Scope.t()) :: [binary()]
  defdelegate capabilities(scope), to: ReviewAccess

  @doc "The fresh scope and mission when the scope's user may author, request or review commands."
  # todo(authz): Cedar should decide who may author and request each command (any mission
  # operator today, DECISIONS #62), e.g. by significance, hazard or target.
  defdelegate authorize(scope, mission_id), to: ReviewAccess

  @spec fetch_command_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  defdelegate fetch_command_request(organization_id, mission_id, command_request_id),
    to: RequestStore,
    as: :fetch_request
end
