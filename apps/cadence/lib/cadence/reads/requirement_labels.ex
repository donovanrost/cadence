defmodule Cadence.Reads.RequirementLabels do
  @moduledoc """
  A requirement's name for people (ux U73, U74). A requirement has no name of its own, so:

    * one generated from a template is called by its template's name ("Block 1 daily");
    * otherwise by its rule in words ("2 downlink contacts of at least 8 min"), the same text
      plan detail's `demand.rules[].text` shows.

  Each label also carries the requirement version's spacecraft (`{id, name}`, or `nil`). A
  requirement that can't be read has no entry.
  """

  import Ecto.Query

  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates}
  alias Cadence.Management.Contacts
  alias Cadence.Reads.ContactPlanOverview.Demand
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @type ref :: {binary(), pos_integer() | nil}

  @doc """
  `%{ref => %{name, spacecraft}}` for `refs` (`{requirement_id, version}`; a `nil` version means
  the current one).
  """
  @spec load(binary(), binary(), [ref()]) :: %{ref() => map()}
  def load(_org, _mission, []), do: %{}

  def load(org, mission, refs) do
    refs = Enum.uniq(refs)
    versions = for ref <- refs, {:ok, v} <- [version(org, mission, ref)], into: %{}, do: {ref, v}

    templates =
      template_names(
        org,
        mission,
        versions |> Map.values() |> Enum.map(& &1.contact_requirement_id)
      )

    crafts = craft_names(org, mission, versions |> Map.values() |> Enum.map(& &1.spacecraft_id))

    Map.new(versions, fn {ref, v} ->
      {ref,
       %{
         name: Map.get(templates, v.contact_requirement_id) || Demand.rule_text(v),
         spacecraft:
           v.spacecraft_id && %{id: v.spacecraft_id, name: Map.get(crafts, v.spacecraft_id)}
       }}
    end)
  end

  defp version(org, mission, {id, nil}) do
    case ContactRequirements.fetch(org, mission, id) do
      {:ok, _requirement, version} -> {:ok, version}
      _missing -> :error
    end
  end

  defp version(org, mission, {id, number}),
    do: Contacts.fetch_requirement_version(org, mission, id, number)

  # Requirement id => its template's (current) name, for requirements a template generated.
  defp template_names(_org, _mission, []), do: %{}

  defp template_names(org, mission, ids) do
    by_requirement =
      from(o in "contact_requirement_occurrences",
        where:
          o.organization_id == ^org and o.mission_id == ^mission and
            o.generated_contact_requirement_id in ^Enum.uniq(ids),
        select: {o.generated_contact_requirement_id, o.contact_requirement_template_id}
      )
      |> Repo.all()
      |> Map.new()

    if by_requirement == %{} do
      %{}
    else
      names =
        org
        |> ContactRequirementTemplates.list(mission)
        |> Map.new(fn {template, version} ->
          {template.contact_requirement_template_id, version.name}
        end)

      Map.new(by_requirement, fn {requirement, template} ->
        {requirement, Map.get(names, template)}
      end)
    end
  end

  defp craft_names(org, mission, ids) do
    case ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        %{}

      ids ->
        case SpacecraftStore.display_names(org, mission, ids) do
          {:ok, rows} -> Map.new(rows, &{&1["id"], &1["name"] || &1["id"]})
          _error -> %{}
        end
    end
  end
end
