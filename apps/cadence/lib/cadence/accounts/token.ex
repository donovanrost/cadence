defmodule Cadence.Accounts.Token do
  @moduledoc false

  @spec generate() :: binary()
  def generate do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec digest(binary()) :: binary()
  def digest(token) when is_binary(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  @spec hint(binary()) :: binary()
  def hint(token) when is_binary(token) do
    String.slice(token, -6, 6)
  end
end
