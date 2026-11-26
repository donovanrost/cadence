defmodule Cadence.Management.Commanding.ReviewPrecondition do
  @moduledoc "Opaque versioned precondition over the exact persisted command request reviewed by an operator."
  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}

  def digest(%CommandRequest{} = request) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({:command_review_v1, Map.from_struct(request)}, [:deterministic])
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
