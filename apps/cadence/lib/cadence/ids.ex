defmodule Cadence.Ids do
  @moduledoc "Stable identifiers and safe route-segment validation."

  @boot_id_key {__MODULE__, :boot_id}
  @max_identifier_bytes 120
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9_.:-]*\z/
  @managed_source_endpoint_prefix "spacecraft_runtime:"

  @doc "Builds the persisted ID for a spacecraft's managed source endpoint."
  @spec managed_source_endpoint_id(binary()) :: binary()
  def managed_source_endpoint_id(spacecraft_id),
    do: @managed_source_endpoint_prefix <> spacecraft_id

  @doc "Returns the spacecraft ID encoded in a managed source endpoint ID."
  @spec spacecraft_id_from_managed_source_endpoint(term()) :: binary() | nil
  def spacecraft_id_from_managed_source_endpoint(
        @managed_source_endpoint_prefix <> spacecraft_id
      ),
      do: spacecraft_id

  def spacecraft_id_from_managed_source_endpoint(_endpoint_id), do: nil

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
