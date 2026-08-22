defmodule Cadence.Ids do
  @moduledoc false

  @boot_id_key {__MODULE__, :boot_id}

  @spec new(binary()) :: binary()
  def new(prefix) when is_binary(prefix) do
    prefix <> "_" <> boot_id() <> "_" <> sequence_suffix()
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
