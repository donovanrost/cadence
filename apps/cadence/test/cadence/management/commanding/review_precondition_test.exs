defmodule Cadence.Management.Commanding.ReviewPreconditionTest do
  @moduledoc """
  DECISIONS #108 for the review token, which #117 stores as a decision record's `subject_digest`:
  an explicit, versioned basis, pinned by a golden value, that a struct change can't move silently.
  """
  use ExUnit.Case, async: true

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Management.Commanding.ReviewPrecondition

  @golden "d72c4665f93b5017a27d75e879b89469f3c8c9b4eb8507b676d3583d0a08358a"

  defp request do
    CommandRequest.new(%{
      command_request_id: "cmdreq-golden",
      organization_id: "org-golden",
      mission_id: "mission-golden",
      source_endpoint_ref: "endpoint-golden",
      mission_model_revision_id: "model-golden",
      command_id: "cmd-golden",
      command_name: "SET_MODE",
      lifecycle_state: :approval_pending,
      requested_by: %{"actor_kind" => "user", "user_id" => "requester"},
      argument_values: %{"mode" => 3},
      resolved_argument_values: %{"mode" => 3},
      requested_at: ~U[2026-11-25 12:00:00.000000Z]
    })
  end

  test "every CommandRequest field is either reviewed or deliberately left out" do
    %{reviewed: reviewed, not_reviewed: not_reviewed} = ReviewPrecondition.basis()
    fields = %CommandRequest{} |> Map.from_struct() |> Map.keys() |> MapSet.new()

    assert MapSet.new(reviewed ++ not_reviewed) == fields,
           "add the new CommandRequest field to ReviewPrecondition's @basis (and bump " <>
             "@basis_version) or to @not_reviewed"
  end

  test "golden: the basis and its encoding are pinned" do
    assert ReviewPrecondition.basis().version == 2
    assert ReviewPrecondition.digest(request()) == @golden
  end

  test "a field outside the basis doesn't move the digest" do
    assert ReviewPrecondition.digest(Map.put(request(), :added_later, "x")) ==
             ReviewPrecondition.digest(request())
  end

  test "any reviewed change moves it" do
    base = ReviewPrecondition.digest(request())

    for change <- [
          %{resolved_argument_values: %{"mode" => 4}},
          %{priority: 1},
          %{expires_at: ~U[2026-11-26 00:00:00Z]},
          %{lifecycle_state: :approved}
        ] do
      refute ReviewPrecondition.digest(struct!(request(), change)) == base, inspect(change)
    end
  end
end
