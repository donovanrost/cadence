defmodule Cadence.Ids do
  @moduledoc "Stable identifiers and safe route-segment validation."

  @boot_id_key {__MODULE__, :boot_id}
  @max_identifier_bytes 120
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_.:-]*\z/

  @spec new(binary()) :: binary()
  def new(prefix) when is_binary(prefix) do
    prefix <> "_" <> boot_id() <> "_" <> sequence_suffix()
  end

  @doc "Returns whether a persisted identifier is safe to use as one route segment."
  @spec valid_identifier?(term()) :: boolean()
  def valid_identifier?(value)
      when is_binary(value) and byte_size(value) <= @max_identifier_bytes and
             value not in [".", ".."] do
    String.valid?(value) and Regex.match?(@identifier_pattern, value)
  end

  def valid_identifier?(_value), do: false

  @doc "Validates an identifier without encoding or changing its persisted value."
  @spec path_segment(term()) :: {:ok, binary()} | {:error, :invalid_identifier}
  def path_segment(value) do
    if valid_identifier?(value), do: {:ok, value}, else: {:error, :invalid_identifier}
  end

  defp boot_id do
    case :persistent_term.get(@boot_id_key, nil) do
      nil ->
        boot_id =
          6
          |> :crypto.strong_rand_bytes()
          |> Base.encode32(case: :lower, padding: false)

        :persistent_term.put(@boot_id_key, boot_id)
        boot_id

      boot_id ->
        boot_id
    end
  end

  defp sequence_suffix do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string(36)
  end
end
