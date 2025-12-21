defmodule Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository do
  @moduledoc """
  Ecto-based implementation of the AutomationRepository port.

  This adapter provides persistence for automations using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :automation_repository, Cadence.Adapters.Persistence.Ecto.Automations.EctoAutomationRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Automations.AutomationRepository.impl()
      {:ok, automation} = repo.find(id, organization_id)
  """

  @behaviour Cadence.Ports.Repository.Automations.AutomationRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Automations.Automation

  # ===========================================================================
  # AutomationRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, organization_id) do
    query =
      from a in Automation,
        where: a.id == ^id and a.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      automation -> {:ok, automation}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Repo.get(Automation, id) do
      nil -> {:error, :not_found}
      automation -> {:ok, automation}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    trigger_type = Keyword.get(opts, :trigger_type)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from a in Automation,
        where: a.organization_id == ^organization_id,
        order_by: [asc: a.name]

    query = apply_filters(query, mission_id: mission_id, enabled_only: enabled_only, trigger_type: trigger_type)
    query = if limit, do: from(a in query, limit: ^limit, offset: ^offset), else: query

    Repo.all(query)
  end

  @impl true
  def list_enabled_for_mission(organization_id, mission_id) do
    from(a in Automation,
      where: a.organization_id == ^organization_id,
      where: a.mission_id == ^mission_id or is_nil(a.mission_id),
      where: a.enabled == true,
      order_by: [asc: a.name]
    )
    |> Repo.all()
  end

  @impl true
  def save(%Automation{id: nil} = automation) do
    %Automation{}
    |> Automation.changeset(Map.from_struct(automation))
    |> Repo.insert()
  end

  def save(%Automation{} = automation) do
    automation
    |> Automation.changeset(Map.from_struct(automation))
    |> Repo.update()
  end

  @impl true
  def delete(%Automation{} = automation) do
    case Repo.delete(automation) do
      {:ok, deleted} -> {:ok, deleted}
      {:error, changeset} -> {:error, extract_errors(changeset)}
    end
  end

  @impl true
  def record_trigger(%Automation{} = automation) do
    automation
    |> Automation.trigger_changeset(%{
      last_triggered_at: DateTime.utc_now(),
      trigger_count: (automation.trigger_count || 0) + 1
    })
    |> Repo.update()
  end

  @impl true
  def enable(%Automation{} = automation) do
    automation
    |> Automation.changeset(%{enabled: true})
    |> Repo.update()
  end

  @impl true
  def disable(%Automation{} = automation) do
    automation
    |> Automation.changeset(%{enabled: false})
    |> Repo.update()
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:mission_id, nil}, q ->
        q

      {:mission_id, mission_id}, q ->
        from(a in q, where: a.mission_id == ^mission_id or is_nil(a.mission_id))

      {:enabled_only, false}, q ->
        q

      {:enabled_only, true}, q ->
        from(a in q, where: a.enabled == true)

      {:trigger_type, nil}, q ->
        q

      {:trigger_type, trigger_type}, q ->
        from(a in q, where: a.trigger_type == ^trigger_type)
    end)
  end

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    {:validation,
     Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
       Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
         opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
       end)
     end)}
  end
end
