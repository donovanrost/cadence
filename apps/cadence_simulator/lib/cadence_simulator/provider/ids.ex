defmodule CadenceSimulator.Provider.Ids do
  @moduledoc false

  @spec new(binary()) :: binary()
  def new(prefix) when is_binary(prefix) do
    suffix =
      10
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "#{prefix}-#{suffix}"
  end

  @spec stable(binary(), iodata()) :: binary()
  def stable(prefix, value) when is_binary(prefix) do
    suffix =
      value
      |> IO.iodata_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 18)

    "#{prefix}-#{suffix}"
  end
end
