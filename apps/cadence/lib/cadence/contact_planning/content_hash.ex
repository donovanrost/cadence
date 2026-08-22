defmodule Cadence.ContactPlanning.ContentHash do
  @moduledoc false

  alias Cadence.Persistence.JsonDocument

  @spec sha256(term()) :: binary()
  def sha256(value) do
    value
    |> JsonDocument.encode()
    |> then(&:erlang.term_to_binary(&1, [:deterministic]))
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
