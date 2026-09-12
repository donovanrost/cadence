defmodule Cadence.Commanding.AuthoringIdentity do
  @moduledoc "Stable deterministic identities for server-owned command authoring evidence."

  def digest(value) do
    {:command_authoring_v1, value}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
