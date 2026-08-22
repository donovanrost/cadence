defmodule CCSDS.TestSupport.NormativeVectors do
  @moduledoc false

  @path Path.expand("../../conformance/normative_vectors.exs", __DIR__)
  @external_resource @path

  {corpus, _binding} = Code.eval_file(@path)
  @corpus corpus

  def corpus, do: @corpus
  def sources, do: @corpus.sources
  def vectors, do: @corpus.vectors

  def vectors_for(subject) do
    Enum.filter(@corpus.vectors, &(&1.subject == subject))
  end

  def vector!(id) do
    Enum.find(@corpus.vectors, &(&1.id == id)) ||
      raise ArgumentError, "unknown normative vector #{inspect(id)}"
  end

  def decode_hex!(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> binary
      :error -> raise ArgumentError, "invalid conformance hex #{inspect(hex)}"
    end
  end
end
