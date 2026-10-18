defmodule Cadence.Reads.ApplicationSurfaces.Planning.TemplateLedger do
  @moduledoc "Authorized semantic recurring-demand ledger and bounded editor choices."
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.ContactRequirementTemplates
  alias Cadence.Missions
  alias Cadence.SpacecraftStore

  def defaults do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      anchor_at: DateTime.to_iso8601(now),
      time_utc: now |> DateTime.to_time() |> Time.to_iso8601()
    }
  end

  def load(scope, mission, defaults, pages) do
    with true <- is_nil(scope.mission_id) or scope.mission_id == mission,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission) do
      can_manage =
        Policy.authorize(scope, :manage_mission, %{
          organization_id: scope.organization_id,
          mission_id: mission
        }) == :ok

      templates =
        ContactRequirementTemplates.list(scope.organization_id, mission, page: pages.templates)

      spacecraft =
        SpacecraftStore.list_spacecraft_page(scope.organization_id, mission,
          page: pages.spacecraft,
          page_size: 25
        )

      {:ok,
       %{
         contract_version: 1,
         context: %{
           organization_id: scope.organization_id,
           mission_id: mission,
           actor_id: scope.user.user_id
         },
         defaults: defaults,
         can_manage: can_manage,
         templates: %{
           page: pages.templates,
           more: length(templates) > 25,
           entries: templates |> Enum.take(25) |> Enum.map(&entry/1)
         },
         spacecraft: %{
           page: spacecraft.page,
           total: spacecraft.total_count,
           entries: Enum.map(spacecraft.items, &%{id: &1.spacecraft_id, name: &1.display_name})
         }
       }}
    else
      false -> {:error, :scope_mismatch}
      error -> error
    end
  end

  defp entry({template, version}) do
    %{
      reference: ContactRequirementTemplates.reference(template, version),
      spacecraft_id: version.spacecraft_id,
      contact_intent: version.requirement_document["contact_intent"],
      schedule: version.schedule_document
    }
  end
end
