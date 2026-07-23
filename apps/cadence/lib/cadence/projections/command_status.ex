defmodule Cadence.Projections.CommandStatus do
  @moduledoc """
  Read-side boundary for command queue, release, and verification state.

  The backing stores remain in the domain-first Commanding context while the
  migration is in progress; callers no longer share its mutation façade.
  """

  alias Cadence.Commanding, as: LegacyCommanding

  defdelegate fetch_queue_entry(organization_id, mission_id, command_queue_entry_id),
    to: LegacyCommanding,
    as: :fetch_command_queue_entry

  defdelegate list_queue_entries(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding,
    as: :list_command_queue_entries

  defdelegate fetch_release_attempt(organization_id, mission_id, command_release_attempt_id),
    to: LegacyCommanding,
    as: :fetch_command_release_attempt

  defdelegate list_release_attempts(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding,
    as: :list_command_release_attempts

  defdelegate fetch_verifier_instance(
                organization_id,
                mission_id,
                command_verifier_instance_id
              ),
              to: LegacyCommanding,
              as: :fetch_command_verifier_instance

  defdelegate list_verifier_instances(organization_id, mission_id, opts \\ []),
    to: LegacyCommanding,
    as: :list_command_verifier_instances
end
