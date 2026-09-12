defmodule Cadence.Missions.Creation do
  @moduledoc "Scoped mission creation independent of frontend installation or release identity."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.{Ids, Missions}
  alias Cadence.Missions.Mission

  def validate(%{"mission" => params}) when is_map(params) do
    with {:ok, name} <- field(params, "display_name"),
         {:ok, slug} <- field(params, "slug"),
         true <- Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, slug) do
      {:ok, %{"mission" => %{"display_name" => name, "slug" => slug}}}
    else
      false -> {:error, %{"slug" => ["Use lowercase letters, numbers, and hyphens."]}}
      {:error, _} = error -> error
    end
  end

  def validate(_params), do: {:error, %{"display_name" => ["Enter valid mission details."]}}

  def create(%Scope{} = scope, params) do
    with :ok <-
           Policy.authorize(scope, :operate_organization, %{
             organization_id: scope.organization_id
           }),
         {:ok, %{"mission" => values}} <- validate(params),
         {:ok, mission} <-
           Missions.persist_mission(%Mission{
             mission_id: Ids.new("mission"),
             organization_id: scope.organization_id,
             display_name: values["display_name"],
             slug: values["slug"]
           }) do
      {:ok,
       %{
         "mission" => %{
           "id" => mission.mission_id,
           "display_name" => mission.display_name,
           "slug" => mission.slug,
           "href" => "/missions/#{mission.mission_id}"
         }
       }}
    end
  end

  defp field(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and byte_size(value) <= 255 ->
        if String.valid?(value) and String.trim(value) != "",
          do: {:ok, String.trim(value)},
          else: {:error, %{key => ["Enter a value."]}}

      _ ->
        {:error, %{key => ["Enter text within 255 bytes."]}}
    end
  end
end
