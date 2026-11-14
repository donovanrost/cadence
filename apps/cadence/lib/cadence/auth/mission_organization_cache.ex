defmodule Cadence.Auth.MissionOrganizationCache do
  @moduledoc """
  Which missions belong to which organization, as `Auth.Policy` has confirmed them (director's
  defense in depth: `:operate_mission` checks a mission is the organization's). A mission never
  changes organization, so a confirmed pair stays true; only confirmed pairs are stored, anything
  else is asked again. The table is read concurrently by every caller; this process only owns it.

  Without the table (a boot that doesn't start it), lookups just miss and `Policy` asks the
  database every time.
  """

  use GenServer

  @table :cadence_mission_organization_pairs

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec confirmed?(binary(), binary()) :: boolean()
  def confirmed?(organization_id, mission_id) do
    :ets.member(@table, {organization_id, mission_id})
  rescue
    ArgumentError -> false
  end

  @spec confirm(binary(), binary()) :: :ok
  def confirm(organization_id, mission_id) do
    :ets.insert(@table, {{organization_id, mission_id}})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
