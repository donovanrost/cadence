defmodule Cadence.Applications.SettingsSectionDefinition do
  @moduledoc "Compiled application contribution to organization and mission settings."
  @enforce_keys [:id, :title, :description, :scopes, :provider]
  defstruct [:id, :title, :description, :scopes, :provider]

  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          description: binary(),
          scopes: [:organization | :mission],
          provider: module()
        }

  def validate(%__MODULE__{} = section) do
    if text?(section.id, 128) and Regex.match?(~r/^[a-z][a-z0-9._-]*$/, section.id) and
         is_atom(section.provider) and not is_nil(section.provider) and
         text?(section.title, 80) and text?(section.description, 400) and
         valid_scopes?(section.scopes),
       do: :ok,
       else: {:error, :invalid_settings_section}
  end

  def validate(_), do: {:error, :invalid_settings_section}

  defp valid_scopes?(scopes) when is_list(scopes) do
    length(scopes) in 1..2 and Enum.all?(scopes, &(&1 in [:organization, :mission])) and
      Enum.uniq(scopes) == scopes
  end

  defp valid_scopes?(_), do: false

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and String.trim(value) != ""
end
