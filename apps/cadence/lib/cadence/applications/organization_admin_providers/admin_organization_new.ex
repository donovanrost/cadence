defmodule Cadence.Applications.OrganizationAdminProviders.AdminOrganizationNew do
  @moduledoc "Compatibility destination and delegate to the authoritative creation effect."
  alias Cadence.Administration.OrganizationCreation

  def props, do: %{}

  def form(params) when is_map(params),
    do: %{display_name: string_param(params, "display_name"), slug: string_param(params, "slug")}

  def create(scope, params) do
    case OrganizationCreation.create(scope, params) do
      {:ok, _organization} -> {:ok, %{navigate: "/admin/organizations"}}
      {:invalid, _errors} -> {:error, :invalid_organization}
      other -> other
    end
  end

  defp string_param(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end
end
