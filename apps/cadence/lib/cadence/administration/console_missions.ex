defmodule Cadence.Administration.ConsoleMissions do
  @moduledoc """
  Console mission create (§11 L4; fe-setup's docs/apogee/plans/mission-create.md): a slug check
  and the create, in the organization the path names. Organization admins and platform admins
  (Policy `:create_missions`). A slug is unique within its organization; a taken one comes back
  with a free variant to suggest, the way AD1 does it for organizations.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.{Ids, Missions}
  alias Cadence.Missions.Mission

  @slug ~r/^[a-z0-9][a-z0-9-]*$/

  @doc "`{slug, available, suggestion | nil}`."
  @spec slug(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def slug(%Scope{} = scope, organization_id, slug) when is_binary(slug) do
    with :ok <- authorize(scope, organization_id) do
      slug = String.trim(slug)
      taken = taken(organization_id)
      available = not MapSet.member?(taken, slug)

      {:ok,
       %{
         slug: slug,
         available: available,
         suggestion: if(available, do: nil, else: suggestion(slug, taken))
       }}
    end
  end

  @doc """
  Creates the mission: `{:ok, %{id, name, slug}}`, or `{:invalid, details}` with flat field
  messages (`name`, `slug` plus `suggestion`), as AD1's.
  """
  @spec create(Scope.t(), binary(), map()) :: {:ok, map()} | {:invalid, map()} | {:error, term()}
  def create(%Scope{} = scope, organization_id, params) do
    with :ok <- authorize(scope, organization_id),
         {:ok, name, slug} <- validate(params) do
      taken = taken(organization_id)

      if MapSet.member?(taken, slug) do
        taken_slug(slug, taken)
      else
        persist(organization_id, name, slug, taken)
      end
    end
  end

  defp persist(organization_id, name, slug, taken) do
    case Missions.persist_mission(%Mission{
           mission_id: Ids.new("mission"),
           organization_id: organization_id,
           display_name: name,
           slug: slug
         }) do
      {:ok, mission} ->
        {:ok, %{id: mission.mission_id, name: mission.display_name, slug: mission.slug}}

      # Someone took the slug between the check and the insert (missions_org_slug_idx).
      {:error, %Ecto.Changeset{}} ->
        taken_slug(slug, MapSet.put(taken, slug))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp taken_slug(slug, taken),
    do:
      {:invalid,
       %{
         "slug" => "That slug is already used in this organization.",
         "suggestion" => suggestion(slug, taken)
       }}

  defp validate(params) when is_map(params) do
    name = text(params["name"])
    slug = text(params["slug"])

    errors =
      %{}
      |> then(
        &if(name, do: &1, else: Map.put(&1, "name", "Enter a name (at most 120 characters)."))
      )
      |> then(fn errors ->
        cond do
          is_nil(slug) or String.length(slug) > 64 ->
            Map.put(errors, "slug", "Enter a slug (at most 64 characters).")

          not Regex.match?(@slug, slug) ->
            Map.put(errors, "slug", "Use lowercase letters, numbers and hyphens.")

          true ->
            errors
        end
      end)

    if errors == %{}, do: {:ok, name, slug}, else: {:invalid, errors}
  end

  defp validate(_params), do: {:invalid, %{"name" => "Enter a name.", "slug" => "Enter a slug."}}

  defp text(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "" and String.length(trimmed) <= 120 and String.valid?(trimmed), do: trimmed
  end

  defp text(_value), do: nil

  defp taken(organization_id),
    do: organization_id |> Missions.list_missions() |> MapSet.new(& &1.slug)

  defp suggestion(slug, taken),
    do:
      Enum.find_value(2..50, fn n ->
        if MapSet.member?(taken, "#{slug}-#{n}"), do: nil, else: "#{slug}-#{n}"
      end)

  defp authorize(scope, organization_id),
    do: Policy.authorize(scope, :create_missions, %{organization_id: organization_id})
end
