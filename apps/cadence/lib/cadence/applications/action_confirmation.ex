defmodule Cadence.Applications.ActionConfirmation do
  @moduledoc "Host-owned confirmation copy for a typed application action."

  @type tone :: :attention | :danger

  @type t :: %__MODULE__{
          title: binary(),
          message: binary(),
          confirm_label: binary(),
          tone: tone()
        }

  @enforce_keys [:title, :message, :confirm_label, :tone]
  defstruct [:title, :message, :confirm_label, :tone]

  @spec validate(t()) :: :ok | {:error, :invalid_application_action_confirmation}
  def validate(%__MODULE__{} = confirmation) do
    if valid_text?(confirmation.title) and valid_text?(confirmation.message) and
         valid_text?(confirmation.confirm_label) and confirmation.tone in [:attention, :danger] do
      :ok
    else
      {:error, :invalid_application_action_confirmation}
    end
  end

  def validate(_confirmation), do: {:error, :invalid_application_action_confirmation}

  @spec prompt(t()) :: binary()
  def prompt(%__MODULE__{} = confirmation) do
    confirmation.title <> "\n\n" <> confirmation.message
  end

  defp valid_text?(value), do: is_binary(value) and value != ""
end
