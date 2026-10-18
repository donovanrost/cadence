defmodule Cadence.Reads.Spacecraft.Configuration do
  @moduledoc "Spacecraft workspace read model with explicit saved and active configuration evidence."
  alias Cadence.Auth.Policy
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Reads.Spacecraft.ConfigurationCatalogs
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftTypeStore

  def load(scope, mission, id, section)
      when section in ["overview", "catalog", "communications", "changes"] do
    with {:ok, _, craft} <- ConfigurationDrafts.authorize(scope, mission.mission_id, id) do
      ConfigurationLock.run(mission.organization_id, mission.mission_id, fn ->
        load_locked(scope, mission, craft, section)
      end)
    end
  end

  def load(_, _, _, _), do: {:error, :invalid_spacecraft_section}

  defp load_locked(scope, mission, craft, section) do
    id = craft.spacecraft_id

    with {:ok, active} <- ConfigurationActive.load(mission) do
      current = ConfigurationDrafts.snapshot(mission, craft)
      approval = ActivationPolicy.load(mission.organization_id, mission.mission_id)
      active_entry = active.entries[id]

      catalogs =
        ConfigurationCatalogs.list(mission, [
          current.document["catalog_revision_id"],
          active_entry && active_entry["catalog_revision_id"]
        ])

      fleet =
        SpacecraftStore.list_spacecraft_page(mission.organization_id, mission.mission_id,
          page_size: 100
        )

      sources =
        SourceEndpoints.list_source_endpoints_page(
          mission.organization_id,
          mission.mission_id,
          spacecraft_id: id,
          page_size: 100
        )

      fleet_items =
        [craft | Enum.reject(fleet.items, &(&1.spacecraft_id == id))] |> Enum.take(100)

      base = "/missions/#{mission.mission_id}/spacecraft/#{id}"

      {:ok,
       %{
         organization_id: mission.organization_id,
         mission_id: mission.mission_id,
         mission_name: mission.display_name,
         spacecraft_id: id,
         name: craft.display_name,
         scid: craft.scid,
         section: section,
         base_href: base,
         token: current.token,
         saved_version: current.row && current.row.version,
         document: current.document,
         external_changes: current.external_changes,
         active:
           active_entry &&
             %{
               version: active_entry["configuration_version"],
               document: active_entry["document"],
               generation: active.activation.generation
             },
         review: review(mission, id, current, active),
         approval: %{
           requirement: approval.effective["approval_requirement"],
           token: approval.token,
           source: approval.source,
           actor_id: scope.user.user_id,
           can_request:
             Policy.authorize(scope, :request_activation, %{
               organization_id: mission.organization_id,
               mission_id: mission.mission_id
             }) == :ok,
           can_review: Activations.authorize_review(scope, mission.mission_id) == :ok
         },
         catalogs: catalogs,
         fleet:
           Enum.map(fleet_items, fn item ->
             row =
               ConfigurationDrafts.latest(
                 mission.organization_id,
                 mission.mission_id,
                 item.spacecraft_id
               )

             entry = active.entries[item.spacecraft_id]

             %{
               id: item.spacecraft_id,
               name: item.display_name,
               scid: item.scid,
               active_catalog_id: entry && entry["catalog_revision_id"],
               has_changes:
                 row != nil and
                   (entry == nil or
                      row.configuration_revision_id != entry["configuration_revision_id"]),
               href:
                 "/missions/#{mission.mission_id}/spacecraft/#{item.spacecraft_id}?section=#{section}"
             }
           end),
         fleet_total: fleet.total_count,
         sources: Enum.map(sources.items, &%{id: &1.source_endpoint_id, name: &1.display_name}),
         presets: presets(mission),
         links: %{
           catalog: "/missions/#{mission.mission_id}/catalog",
           identity: base <> "/identity",
           applications: base <> "/applications",
           communications: "/missions/#{mission.mission_id}/comms",
           readiness: base <> "/readiness",
           approvals: "/missions/#{mission.mission_id}/ops/activations",
           settings: "/missions/#{mission.mission_id}/settings/cadence.governance",
           ops: ops_href(mission, active_entry)
         }
       }}
    end
  end

  defp presets(mission) do
    SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)
    |> Enum.reject(&Map.has_key?(&1.metadata, "spacecraft_configuration_revision_id"))
    |> Enum.take(100)
    |> Enum.map(
      &%{
        id: &1.spacecraft_type_id,
        version: &1.version,
        name: &1.display_name,
        protocol: ConfigurationInput.from_profile(&1)
      }
    )
  end

  defp ops_href(_mission, nil), do: nil

  defp ops_href(mission, %{"commanding_enabled" => true, "source_endpoint_ids" => [id | _]}),
    do: "/missions/#{mission.mission_id}/ops/commands/workspace?target=#{URI.encode_www_form(id)}"

  defp ops_href(_, _), do: nil

  defp review(mission, id, current, active) do
    request =
      Activations.latest_spacecraft_request(mission.organization_id, mission.mission_id, id)

    if request do
      evidence = request.metadata["configuration_review"]

      applied =
        get_in(active.entries, [id, "configuration_revision_id"]) ==
          evidence["configuration_revision_id"]

      state =
        cond do
          applied -> applied_state(request.activation_request_id)
          stale_review?(request, mission, current, active, evidence) -> "stale"
          true -> to_string(request.state)
        end

      %{
        id: request.activation_request_id,
        state: state,
        requester_id: request.requester_actor_id,
        version:
          get_in(request.metadata, ["spacecraft_configurations", id, "configuration_version"])
      }
    else
      nil
    end
  end

  defp applied_state(request_id) do
    case ControlActivations.fetch_execution(request_id) do
      {:ok, %{status: :succeeded}} -> "active"
      {:ok, _execution} -> "approved"
      {:error, :activation_execution_not_found} -> "active"
    end
  end

  defp stale_review?(request, mission, current, active, evidence) do
    not ActivationPolicy.current?(
      mission.organization_id,
      mission.mission_id,
      request.policy_document
    ) or
      evidence["configuration_token"] != current.token or
      evidence["base_activation_id"] != (active.activation && active.activation.activation_id)
  end
end
