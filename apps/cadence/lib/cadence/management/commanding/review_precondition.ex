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
