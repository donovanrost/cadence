defmodule Cadence.Applications.SurfaceElements.Stat do
  @moduledoc "Host-rendered summary fact for a declarative application surface."

  @type tone :: :ready | :attention | :blocked | :info
  @type t :: %__MODULE__{id: binary(), label: binary(), value: binary(), tone: tone()}

  @enforce_keys [:id, :label, :value]
  defstruct [:id, :label, :value, tone: :info]

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_stat}
  def validate(%__MODULE__{} = stat) do
    if valid_text?(stat.id) and valid_text?(stat.label) and valid_text?(stat.value) and
         stat.tone in [:ready, :attention, :blocked, :info] do
      :ok
    else
      {:error, :invalid_application_surface_stat}
    end
  end

  def validate(_stat), do: {:error, :invalid_application_surface_stat}

  defp valid_text?(value), do: is_binary(value) and value != ""
end
