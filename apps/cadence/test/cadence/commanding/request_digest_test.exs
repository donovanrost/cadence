defmodule Cadence.Commanding.RequestDigestTest do
  @moduledoc """
  DECISIONS #108 for the review token, which #117 stores as a decision record's `subject_digest`
  (DECISIONS #112): an explicit, versioned basis, pinned by a golden value, that a struct change
  can't move silently. Version 3 (#708) reviews the request's group with it.
  """
  use ExUnit.Case, async: true

  alias Cadence.Commanding.{CommandRequest, RequestDigest}

  @golden "c3131f74cf088af915d1f04a8496aea347cf2994257ef9b927ac79bcb547fd88"

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
      requested_at: ~U[2026-11-25 12:00:00.000000Z],
      command_group_id: "group-golden",
      group_target_index: 2,
      group_position: 1
    })
  end

  test "every CommandRequest field is either reviewed or deliberately left out" do
    %{reviewed: reviewed, not_reviewed: not_reviewed} = RequestDigest.basis()
    fields = %CommandRequest{} |> Map.from_struct() |> Map.keys() |> MapSet.new()

    assert MapSet.new(reviewed ++ not_reviewed) == fields,
           "add the new CommandRequest field to RequestDigest's @basis (and bump " <>
             "@basis_version) or to @not_reviewed"
  end

  test "golden: the basis and its encoding are pinned" do
    assert RequestDigest.basis().version == 3
    assert RequestDigest.digest(request()) == @golden
  end

  test "any reviewed change moves it, the group's place included" do
    base = RequestDigest.digest(request())

    for change <- [
          %{resolved_argument_values: %{"mode" => 4}},
          %{priority: 1},
          %{expires_at: ~U[2026-11-26 00:00:00Z]},
          %{lifecycle_state: :approved},
          %{command_group_id: "another-group"},
          %{group_target_index: 3},
          %{group_position: 2}
        ] do
      refute RequestDigest.digest(struct!(request(), change)) == base, inspect(change)
    end
  end
end
