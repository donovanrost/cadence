defmodule Cadence.Reads.WindowCursor do
  @moduledoc "A cursor for a time-window read ordered by timestamp and a stable row key."

  @spec encode(DateTime.t(), binary(), integer(), term()) :: binary()
  def encode(at, id, kind, basis) do
    [DateTime.to_iso8601(at), id, kind, fingerprint(basis)]
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(binary() | nil, term(), [integer()]) ::
          {:ok, {DateTime.t(), binary(), integer()} | nil} | {:error, :invalid_cursor}
  def decode(nil, _basis, _kinds), do: {:ok, nil}

  def decode(token, basis, kinds) when is_binary(token) and byte_size(token) <= 2_048 do
    with {:ok, bytes} <- Base.url_decode64(token, padding: false),
         {:ok, [time, id, kind, hash]} <- Jason.decode(bytes),
         true <- is_binary(time) and is_binary(id) and byte_size(id) > 0,
         :nomatch <- :binary.match(id, <<0>>),
         true <- kind in kinds and hash == fingerprint(basis),
         {:ok, at, _offset} <- DateTime.from_iso8601(time) do
      {:ok, {at, id, kind}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  def decode(_token, _basis, _kinds), do: {:error, :invalid_cursor}

  defp fingerprint(basis) do
    basis
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
