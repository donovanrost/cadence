defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactPlanShow do
  @moduledoc "Bounded immutable plan review for an authorized mission surface."

  alias Cadence.Auth.Scope
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Reads.ApplicationSurfaces.Planning.PlanDetailProjection

  @pages ~w(versions_page approvals_page opportunities_page execution_page requirements_page issues_page)
  @keys ~w(contact_plan_id version) ++ @pages

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(params, fn {key, value} -> key in @keys and identifier?(value) end),
         true <- identifier?(params["contact_plan_id"]),
         {:ok, version} <- optional_version(params["version"]),
         {:ok, pages} <- pages(params) do
      {:ok,
       Map.merge(pages, %{"contact_plan_id" => params["contact_plan_id"], "version" => version})}
    else
      _ -> {:error, :invalid_plan_detail_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_plan_detail_query}

  def load(%Scope{} = scope, mission, params) do
    org = scope.organization_id
    mission_id = mission.mission_id

    with {:ok, query} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, plan, current} <-
           ManagementContacts.fetch_plan(org, mission_id, query["contact_plan_id"]),
         {:ok, reviewed} <- reviewed_version(org, mission_id, plan, current, query["version"]),
         query = Map.put(query, "version", reviewed.version),
         {:ok, evidence} <-
           evidence(org, mission_id, plan.contact_plan_id, reviewed.version, query),
         {:ok, decisions} <-
           ManagementContacts.list_plan_approvals_page(
             org,
             mission_id,
             plan.contact_plan_id,
             reviewed.version,
             1
           ) do
      decision = Enum.find(decisions.entries, &(&1.contact_plan_version == reviewed.version))

      {:ok,
       %{detail: PlanDetailProjection.project(scope, plan, reviewed, decision, query, evidence)}}
    end
  end

  defp reviewed_version(_org, _mission, _plan, current, nil), do: {:ok, current}

  defp reviewed_version(org, mission, plan, current, version) when version <= current.version,
    do: ManagementContacts.fetch_plan_version(org, mission, plan.contact_plan_id, version)

  defp reviewed_version(_, _, _, _, _), do: {:error, :future_contact_plan_version}

  defp evidence(org, mission, plan, version, query) do
    with {:ok, versions} <-
           ManagementContacts.list_plan_versions_page(
             org,
             mission,
             plan,
             version,
             query["versions_page"]
           ),
         {:ok, approvals} <-
           ManagementContacts.list_plan_approvals_page(
             org,
             mission,
             plan,
             version,
             query["approvals_page"]
           ),
         {:ok, opportunities} <-
           ManagementContacts.list_plan_opportunities_page(
             org,
             mission,
             plan,
             version,
             query["opportunities_page"]
           ),
         {:ok, execution} <-
           ControlContacts.list_plan_execution_page(
             org,
             mission,
             plan,
             version,
             query["execution_page"]
           ) do
      {:ok,
       %{
         versions: versions,
         approvals: approvals,
         opportunities: opportunities,
         execution: execution
       }}
    end
  end

  defp pages(params) do
    Enum.reduce_while(@pages, {:ok, %{}}, fn key, {:ok, acc} ->
      case number(Map.get(params, key, "1"), 1_000_000) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        _ -> {:halt, {:error, :invalid_page}}
      end
    end)
  end

  defp optional_version(nil), do: {:ok, nil}
  defp optional_version(value), do: number(value, 2_147_483_647)

  defp number(value, maximum) when is_binary(value) do
    with true <- Regex.match?(~r/\A[1-9][0-9]{0,9}\z/, value),
         {integer, ""} when integer <= maximum <- Integer.parse(value) do
      {:ok, integer}
    else
      _ -> {:error, :invalid_integer}
    end
  end

  defp number(_, _), do: {:error, :invalid_integer}

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..240,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x20\x7f]/, value)

  defp identifier?(_), do: false
end
