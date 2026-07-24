defmodule Cadence.Platform.Fingerprint do
  @moduledoc "Plane-neutral stable fingerprints for cache and projection identities."

  @spec url_sha256(term()) :: binary()
  def url_sha256(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
