defmodule Cadence.Management.Commanding.ReviewPrecondition do
  @moduledoc """
  The review token: a digest of exactly the command request an operator reviewed. It is compared
  live (a stale token refuses the decision) and stored as a decision record's `subject_digest`
  (#117), so its basis is explicit and versioned (DECISIONS #108), never a struct term:

  - `@basis` names every reviewed field. A field added to `CommandRequest` is either added here
    (with `@basis_version` bumped) or listed in `@not_reviewed`, and a test fails until one is done.
  - Values are the request's JSON form (`JsonDocument.encode/1`: string keys, ISO 8601 times), so
    the digest doesn't depend on Elixir structs or atoms.
  """
  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}
  alias Cadence.Persistence.JsonDocument

  @basis_version 2
  @basis ~w(command_request_id organization_id mission_id source_endpoint_ref
            mission_model_revision_id command_id command_name command_display_name not_before
            expires_at verification_state source_command_stage_id source_staged_command_item_id
            significance subsystem group_name preferred_uplink_service release_policy_hint apid
            service_type service_subtype opcode requested_at requested_by lifecycle_state priority
            argument_values resolved_argument_values critical hazardous metadata)a
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

  @doc """
  #117 step 4a (four-eyes design B): a caller that opts in with `require_review: true` (the REST
  approve and reject) must send the review token; without it, `:command_review_required` and
  nothing is recorded. It runs after the human-approver check, so that refusal stays the first
  answer (api-ops).
  """
  @spec required(keyword()) :: :ok | {:error, :command_review_required | :command_review_invalid}
  def required(opts) do
    case {Keyword.get(opts, :require_review), Keyword.get(opts, :expected_review)} do
      {true, nil} -> {:error, :command_review_required}
      # api-ops on #631: not a review token at all (64 lowercase hex) is malformed, not stale.
      {true, token} -> if well_formed?(token), do: :ok, else: {:error, :command_review_invalid}
      _not_required -> :ok
    end
  end

  defp well_formed?(token), do: is_binary(token) and String.match?(token, ~r/\A[0-9a-f]{64}\z/)

  def check(%CommandRequestRow{} = row, opts) do
    case Keyword.fetch(opts, :expected_review) do
      :error ->
        :ok

      {:ok, expected} when is_binary(expected) ->
        if expected == digest(CommandRequestRow.to_domain(row)),
          do: :ok,
          else: {:error, :command_review_changed}

      _ ->
        {:error, :command_review_changed}
    end
  end
end
