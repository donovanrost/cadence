defmodule Cadence.CCSDS.CFDP.Directive.Prompt do
  @moduledoc """
  CFDP Prompt directive payload.
  """

  @type response :: :nak | :keep_alive
  @type t :: %__MODULE__{response: response()}

  defstruct response: :nak

  @spec new(response()) :: t()
  def new(response) when response in [:nak, :keep_alive], do: %__MODULE__{response: response}
end
