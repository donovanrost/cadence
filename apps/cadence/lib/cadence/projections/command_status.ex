defmodule Cadence.Projections.CommandStatus do
  @moduledoc """
  Read-side boundary for command queue, release, and verification state.

  The backing stores remain in the domain-first Commanding context while the
  migration is in progress; callers no longer share its mutation façade.
  """

  alias Cadence.Commanding, as: LegacyCommanding
  alias Cadence.Management.Commanding, as: ManagementCommanding

  @spec project(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def project(organization_id, mission_id, command_request_id) do
    with {:ok, request} <-
           ManagementCommanding.fetch_command_request(
             organization_id,
             mission_id,
             command_request_id
           ) do
      by_request = [command_request_id: command_request_id]

      queue_entries =
        LegacyCommanding.list_command_queue_entries(organization_id, mission_id, by_request)

      release_attempts =
        LegacyCommanding.list_command_release_attempts(organization_id, mission_id, by_request)

      verifier_instances =
        LegacyCommanding.list_command_verifier_instances(organization_id, mission_id, by_request)

      {:ok,
       %{
         requested: %{command_request: request},
         operational: %{queue_entries: queue_entries},
         applied: %{release_attempts: release_attempts},
         observed: %{verifier_instances: verifier_instances}
       }}
    end
  end
end
