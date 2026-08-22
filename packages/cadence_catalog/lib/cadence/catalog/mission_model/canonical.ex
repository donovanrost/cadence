defmodule Cadence.Catalog.MissionModel.Canonical do
  @moduledoc """
  Deterministic identities and content hashes for Mission Model artifacts.
  """

  @spec sha256(term()) :: binary()
  def sha256(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec content_id(binary(), term()) :: binary()
  def content_id(prefix, term) when is_binary(prefix) do
    prefix <> ":" <> sha256(term)
  end

  @spec semantic_id(atom(), binary()) :: binary()
  def semantic_id(kind, qualified_name) when is_atom(kind) and is_binary(qualified_name) do
    "semantic:" <> Atom.to_string(kind) <> ":" <> sha256({kind, qualified_name})
  end
end
