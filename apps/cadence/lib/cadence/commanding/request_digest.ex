defmodule Cadence.Commanding.RequestDigest do
  @moduledoc """
  The digest of exactly the command request a group's operators reviewed. It is compared live (a
  stale `expected_review` refuses a group decision), and stored as a decision record's
  `subject_digest` (#117, DECISIONS #112) and in a group's `members_digest`. So its basis is
  explicit and versioned (DECISIONS #108), never a struct term:

  - `@basis` names every reviewed field. A field added to `CommandRequest` is either added here
    (with `@basis_version` bumped) or listed in `@not_reviewed`, and a test fails until one is done.
  - Values are the request's JSON form (`JsonDocument.encode/1`: string keys, ISO 8601 times), so
    the digest doesn't depend on Elixir structs or atoms.

  Version 3 (#708): the request's group (`command_group_id`, `group_slot`) is reviewed with it. Version 2 carried the group inside `metadata["group"]`.
  """
  alias Cadence.Commanding.CommandRequest
  alias Cadence.Persistence.JsonDocument

  @basis_version 3
  @basis ~w(command_request_id organization_id mission_id source_endpoint_ref
            mission_model_revision_id command_id command_name command_display_name not_before
            expires_at verification_state significance subsystem group_name preferred_uplink_service release_policy_hint apid
            service_type service_subtype opcode requested_at requested_by lifecycle_state priority
            argument_values resolved_argument_values critical hazardous metadata
            command_group_id group_slot)a
  @not_reviewed []

  @doc "The reviewed fields, and the fields deliberately left out (for the basis test)."
  @spec basis() :: %{reviewed: [atom()], not_reviewed: [atom()], version: pos_integer()}
  def basis, do: %{reviewed: @basis, not_reviewed: @not_reviewed, version: @basis_version}

  @spec digest(CommandRequest.t()) :: binary()
  def digest(%CommandRequest{} = request) do
    fields = Map.new(@basis, &{Atom.to_string(&1), JsonDocument.encode(Map.fetch!(request, &1))})

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary(["command_review", @basis_version, fields], [:deterministic])
    )
    |> Base.encode16(case: :lower)
  end
end
