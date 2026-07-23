defmodule Cadence.Platform.ContentHash do
  @moduledoc """
  Stable hashing for immutable cross-plane artifacts.
  """

  @spec term_sha256(term()) :: binary()
  def term_sha256(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
