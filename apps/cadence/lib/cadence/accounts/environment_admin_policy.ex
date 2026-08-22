defmodule Cadence.Accounts.EnvironmentAdminPolicy do
  @moduledoc """
  Immutable boot policy for reconciling the environment administrator.

  Runtime authentication relies on the reconciled principal and credential
  rows. This policy is consumed at the application boundary and is not a
  process-global input to sign-in or session validation.
  """

  @derive {Inspect, except: [:password]}
  @enforce_keys [:enabled?]
  defstruct enabled?: false,
            email: nil,
            display_name: "Cadence Administrator",
            password: nil

  @type t :: %__MODULE__{
          enabled?: boolean(),
          email: binary() | nil,
          display_name: binary(),
          password: binary() | nil
        }

  @spec from_config(keyword()) :: t()
  def from_config(config) when is_list(config) do
    email = Keyword.get(config, :email)
    password = Keyword.get(config, :password)

    if Keyword.get(config, :enabled, false) and present?(email) and present?(password) do
      %__MODULE__{
        enabled?: true,
        email: email,
        display_name: Keyword.get(config, :display_name, "Cadence Administrator"),
        password: password
      }
    else
      %__MODULE__{enabled?: false}
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
