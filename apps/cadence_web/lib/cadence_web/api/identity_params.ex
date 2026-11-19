defmodule CadenceWeb.API.IdentityParams do
  @moduledoc "Identity and tenancy request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @spec organization(map()) :: {:ok, Organization.t()} | {:error, term()}
  def organization(params) when is_map(params) do
    with {:ok, slug} <- required_string(params, "slug"),
         {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Organization.new(%{
         organization_id: string_value(params, "organization_id"),
         slug: slug,
         display_name: display_name,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec mission(binary(), map()) :: {:ok, Mission.t()} | {:error, term()}
  def mission(organization_id, params) when is_binary(organization_id) and is_map(params) do
    with {:ok, slug} <- required_string(params, "slug"),
         {:ok, display_name} <- required_string(params, "display_name") do
      {:ok,
       Mission.new(%{
         mission_id: string_value(params, "mission_id"),
         organization_id: organization_id,
         slug: slug,
         display_name: display_name,
         metadata: map_value(params, "metadata")
       })}
    end
  end
end
