defmodule Cadence.ContactPlanning.ContentHash do
  @moduledoc false

  alias Cadence.Persistence.JsonDocument

  @spec sha256(term()) :: binary()
  def sha256(value), do: value |> JsonDocument.encode() |> sha256_json()

  @doc false
  def sha256_json(document) do
    document
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
