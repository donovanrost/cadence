defmodule Cadence.Management.Commanding.RequestReview do
  @moduledoc "Finite human review decisions pinned to the request shown by the host."
  alias Cadence.Ids
  alias Cadence.Management.Commanding
  alias Cadence.Management.Commanding.{ReviewAccess, ReviewPrecondition}

  defdelegate authorize(scope, mission), to: ReviewAccess
  defdelegate review_token(request), to: ReviewPrecondition, as: :digest

  def decide(scope, mission, request, input) do
    with {:ok, fresh, _} <- ReviewAccess.authorize(scope, mission),
         {:ok, _} <- Ids.path_segment(request),
         {:ok, decision, reason, review} <- admit(input) do
      actor = %{"actor_kind" => "user", "user_id" => fresh.user.user_id}
      opts = [reason: reason, expected_review: review]

      result =
        case decision do
          "approved" ->
            Commanding.approve_command_request(
              fresh.organization_id,
              mission,
              request,
              actor,
              opts
            )

          "rejected" ->
            Commanding.reject_command_request(
              fresh.organization_id,
              mission,
              request,
              actor,
              opts
            )
        end

      receipt(result)
    else
      _ ->
        {:rejected,
         "The request is unavailable or your access has changed. Reload before reviewing."}
    end
  end

  defp admit(%{"decision" => decision, "reason" => reason, "expected_review" => review} = input)
       when map_size(input) == 3 and decision in ["approved", "rejected"] and is_binary(reason) and
              is_binary(review) do
    if String.valid?(reason) and byte_size(reason) <= 2000 and
         not Regex.match?(~r/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/, reason) and
         Regex.match?(~r/\A[0-9a-f]{64}\z/, review),
       do: {:ok, decision, String.trim(reason), review},
       else: {:error, :invalid_input}
  end

  defp admit(_), do: {:error, :invalid_input}

  defp receipt({:ok, %{approval: approval, command_request: request}}),
    do:
      {:ok,
       %{
         "approval_id" => approval.command_approval_id,
         "request_id" => request.command_request_id,
         "decision" => Atom.to_string(approval.decision),
         "decided_at" => DateTime.to_iso8601(approval.decided_at),
         "actor_id" => approval.decided_by["user_id"]
       }}

  defp receipt({:error, :command_review_changed}),
    do: {:rejected, "The reviewed request changed. Reload and review its current state."}

  defp receipt({:error, {:command_request_not_pending_approval, _, _}}),
    do: {:rejected, "This request is no longer awaiting a decision."}

  defp receipt({:error, {:command_request_self_approval_not_allowed, _}}),
    do: {:rejected, "A different person must review this request."}

  defp receipt({:error, _}),
    do: {:rejected, "The decision was not saved. Reload before reviewing."}
end
