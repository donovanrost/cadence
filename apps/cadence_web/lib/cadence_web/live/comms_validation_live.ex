defmodule CadenceWeb.CommsValidationLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)
    source_endpoints = Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)
    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

    transport_profiles =
      Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

    findings =
      findings_for_resources(
        scope.organization_id,
        mission.mission_id,
        spacecraft,
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles
      )

    {:ok,
     socket
     |> assign(:page_title, "Comms Validation")
     |> assign(:nav_item, :comms)
     |> assign(:findings, findings)
     |> assign(:finding_groups, finding_groups(findings))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-validation-page" class="space-y-6">
      <.comms_header current_mission={@current_mission} active={:validation} />

      <section class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Setup Checks</p>
              <h2 class="text-lg font-semibold">Comms Validation</h2>
              <p class="mt-1 text-sm text-base-content/60">
                These checks focus on whether saved comms setup can produce usable operational
                paths later. Runtime contact health belongs under the future ops workspace.
              </p>
            </div>
            <.status_badge
              status={if @findings == [], do: :ready, else: :warning}
              label={if @findings == [], do: "No Findings", else: "#{length(@findings)} Findings"}
            />
          </div>

          <%= if @findings == [] do %>
            <div class="mt-6">
              <.empty_state
                icon="hero-check-circle"
                title="No comms setup findings"
                description="This mission has enough comms setup structure for the current validation rules."
              />
            </div>
          <% else %>
            <div id="comms-validation-findings" class="mt-6 space-y-5">
              <section :for={group <- @finding_groups} id={group.id} class="space-y-3">
                <div>
                  <p class="hud-label mb-1">{group.title}</p>
                  <p class="text-sm text-base-content/60">{group.description}</p>
                </div>

                <div
                  :for={finding <- group.findings}
                  class="border border-base-300 bg-base-100/40 p-4"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="font-semibold">{finding.title}</h3>
                      <p class="mt-1 text-sm text-base-content/60">{finding.body}</p>
                      <.link
                        :if={Map.get(finding, :action_navigate)}
                        navigate={finding.action_navigate}
                        class="btn btn-primary btn-xs mt-3"
                      >
                        {Map.get(finding, :action_label, "Review")}
                      </.link>
                    </div>
                    <.status_badge status={finding.severity} label={finding_label(finding.severity)} />
                  </div>
                </div>
              </section>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  def findings_for_mission(organization_id, mission_id) do
    findings_for_resources(
      organization_id,
      mission_id,
      Cadence.list_spacecraft(organization_id, mission_id),
      Cadence.list_source_endpoints(organization_id, mission_id),
      Cadence.list_path_templates(organization_id, mission_id),
      Cadence.list_provider_profiles(organization_id, mission_id),
      Cadence.list_transport_profiles(organization_id, mission_id)
    )
  end

  def findings_for_resources(
        organization_id,
        mission_id,
        spacecraft,
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles
      ) do
    provider_profiles_by_id =
      profile_versions_by_ref(
        provider_profiles,
        path_templates,
        "provider_profile_id",
        &Cadence.list_provider_profile_versions/3,
        organization_id,
        mission_id
      )

    transport_profiles_by_id =
      profile_versions_by_ref(
        transport_profiles,
        path_templates,
        "transport_profile_id",
        &Cadence.list_transport_profile_versions/3,
        organization_id,
        mission_id
      )

    telemetry_configs_by_spacecraft =
      organization_id
      |> TelemetryDecom.list_configs(mission_id)
      |> Map.new(&{&1.spacecraft_id, &1})

    active_telemetry = active_telemetry_activation(organization_id, mission_id)
    link_assignments = Cadence.list_link_assignments(organization_id, mission_id)

    findings(
      source_endpoints,
      path_templates,
      provider_profiles,
      transport_profiles,
      provider_profiles_by_id,
      transport_profiles_by_id,
      mission_id
    )
    |> Kernel.++(
      selected_path_findings(
        [],
        link_assignments,
        Map.new(source_endpoints, &{&1.source_endpoint_id, &1})
      )
    )
    |> Kernel.++(
      link_assignment_findings(
        spacecraft,
        source_endpoints,
        path_templates,
        link_assignments,
        mission_id
      )
    )
    |> Kernel.++(
      spacecraft_interpretation_findings(
        spacecraft,
        telemetry_configs_by_spacecraft,
        active_telemetry,
        mission_id
      )
    )
  end

  def findings(source_endpoints, path_templates) do
    findings(source_endpoints, path_templates, [], [], nil)
  end

  def findings(
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles,
        mission_id
      ) do
    provider_profiles_by_id = Map.new(provider_profiles, &{&1.provider_profile_id, &1})
    transport_profiles_by_id = Map.new(transport_profiles, &{&1.transport_profile_id, &1})

    findings(
      source_endpoints,
      path_templates,
      provider_profiles,
      transport_profiles,
      provider_profiles_by_id,
      transport_profiles_by_id,
      mission_id
    )
  end

  def findings(
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles,
        mission_id,
        link_assignments
      ) do
    provider_profiles_by_id = Map.new(provider_profiles, &{&1.provider_profile_id, &1})
    transport_profiles_by_id = Map.new(transport_profiles, &{&1.transport_profile_id, &1})

    findings(
      source_endpoints,
      path_templates,
      provider_profiles,
      transport_profiles,
      provider_profiles_by_id,
      transport_profiles_by_id,
      mission_id
    )
    |> Kernel.++(
      selected_path_findings(
        [],
        link_assignments,
        Map.new(source_endpoints, &{&1.source_endpoint_id, &1})
      )
    )
  end

  def findings(
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles,
        provider_profiles_by_id,
        transport_profiles_by_id,
        mission_id
      ) do
    endpoint_ids = MapSet.new(source_endpoints, & &1.source_endpoint_id)
    source_endpoints_by_id = Map.new(source_endpoints, &{&1.source_endpoint_id, &1})

    []
    |> add_if(source_endpoints == [], %{
      owner: :link_assignment,
      severity: :missing,
      title: "No runtime identities configured",
      body: "Mission links need runtime identities so ingress can resolve runtime ownership."
    })
    |> add_if(path_templates == [], %{
      owner: :mission_network,
      severity: :missing,
      title: "No link templates configured",
      body: "Operations will need at least one reusable uplink or downlink link template."
    })
    |> Kernel.++(
      path_template_findings(
        path_templates,
        endpoint_ids,
        provider_profiles_by_id,
        transport_profiles_by_id,
        mission_id
      )
    )
    |> Kernel.++(selected_path_findings(path_templates, [], source_endpoints_by_id))
    |> Kernel.++(profile_findings(provider_profiles, transport_profiles))
  end

  def profile_ref_findings(
        path_template,
        provider_profiles_by_id,
        transport_profiles_by_id,
        mission_id
      ) do
    provider_ref_findings(path_template, provider_profiles_by_id, mission_id) ++
      transport_ref_findings(path_template, transport_profiles_by_id, mission_id)
  end

  defp profile_findings(provider_profiles, transport_profiles) do
    []
    |> add_if(provider_profiles == [], %{
      owner: :mission_network,
      severity: :warning,
      title: "No providers configured",
      body:
        "Link templates can be sketched without providers, but operations need providers to connect to external streams."
    })
    |> add_if(transport_profiles == [], %{
      owner: :mission_network,
      severity: :warning,
      title: "No protocol behaviors configured",
      body:
        "Protocol behaviors define reusable link-local behavior such as uplink gateways and heartbeat monitors."
    })
  end

  defp path_template_findings(
         path_templates,
         endpoint_ids,
         provider_profiles_by_id,
         transport_profiles_by_id,
         mission_id
       ) do
    Enum.flat_map(path_templates, fn template ->
      path_name = display_name(template, :path_id)

      []
      |> add_if(
        is_binary(template.source_endpoint_ref) and
          not MapSet.member?(endpoint_ids, template.source_endpoint_ref),
        %{
          owner: :link_assignment,
          severity: :missing,
          title: "#{path_name} references a missing runtime identity",
          body:
            "Update the link template or restore runtime identity #{template.source_endpoint_ref}."
        }
      )
      |> add_if(template.provider_profile_refs == [], %{
        owner: :mission_network,
        severity: :missing,
        title: "#{path_name} has no provider",
        body:
          "A link template without a provider cannot connect to or receive from an external stream."
      })
      |> add_if(template.transport_profile_refs == [], %{
        owner: :mission_network,
        severity: :warning,
        title: "#{path_name} has no protocol behavior",
        body:
          "A link template without protocol behaviors has no configured protocol or transport-extension behavior."
      })
      |> Kernel.++(
        profile_ref_findings(
          template,
          provider_profiles_by_id,
          transport_profiles_by_id,
          mission_id
        )
      )
    end)
  end

  defp provider_ref_findings(path_template, provider_profiles_by_id, mission_id) do
    Enum.flat_map(path_template.provider_profile_refs, fn ref ->
      profile_ref_finding(
        path_template,
        ref,
        "provider_profile_id",
        provider_profiles_by_id,
        :provider_profile_id,
        "provider",
        mission_id
      )
    end)
  end

  defp transport_ref_findings(path_template, transport_profiles_by_id, mission_id) do
    Enum.flat_map(path_template.transport_profile_refs, fn ref ->
      profile_ref_finding(
        path_template,
        ref,
        "transport_profile_id",
        transport_profiles_by_id,
        :transport_profile_id,
        "protocol behavior",
        mission_id
      )
    end)
  end

  defp profile_ref_finding(
         path_template,
         ref,
         id_key,
         profiles_by_id,
         fallback_field,
         profile_label,
         mission_id
       ) do
    path_name = display_name(path_template, :path_id)
    profile_id = Map.get(ref, id_key)
    ref_version = ref_version(ref)

    case Map.fetch(profiles_by_id, profile_id) do
      {:ok, {:archived, archived_profile}} ->
        profile_name = display_name(archived_profile, fallback_field)

        [
          path_action_finding(
            path_template,
            mission_id,
            %{
              owner: :mission_network,
              severity: :missing,
              title: "#{path_name} references an archived #{profile_label}",
              body:
                "#{path_name} still references archived #{profile_name} v#{ref_version}. Create a new link template version with an active #{profile_label}."
            }
          )
        ]

      {:ok, latest_profile} when ref_version < latest_profile.version ->
        profile_name = display_name(latest_profile, fallback_field)

        [
          path_action_finding(
            path_template,
            mission_id,
            %{
              owner: :mission_network,
              severity: :warning,
              title: "#{path_name} uses stale #{profile_label}",
              body:
                "#{path_name} uses #{profile_name} v#{ref_version}; latest is v#{latest_profile.version}."
            }
          )
        ]

      {:ok, _latest_profile} ->
        []

      :error ->
        [
          path_action_finding(
            path_template,
            mission_id,
            %{
              owner: :mission_network,
              severity: :missing,
              title: "#{path_name} references a missing #{profile_label}",
              body: "Update the link template or restore #{profile_label} #{profile_id}."
            }
          )
        ]
    end
  end

  defp path_action_finding(_path_template, nil, finding), do: finding

  defp path_action_finding(path_template, mission_id, finding) do
    Map.merge(finding, %{
      action_label: "Create new link template version",
      action_navigate:
        ~p"/missions/#{mission_id}/comms/link-templates/#{path_template.path_template_id}/new-version"
    })
  end

  defp link_assignment_findings(
         spacecraft,
         source_endpoints,
         path_templates,
         link_assignments,
         mission_id
       ) do
    available_downlinks = SpacecraftCommsReadiness.available_downlink_templates(path_templates)

    Enum.flat_map(spacecraft, fn spacecraft ->
      link_assignment_finding(
        spacecraft,
        spacecraft
        |> SpacecraftCommsReadiness.runtime_identity_match(source_endpoints)
        |> SpacecraftCommsReadiness.runtime_identity_from_match(),
        path_templates,
        link_assignments,
        available_downlinks,
        mission_id
      )
    end)
  end

  defp link_assignment_finding(
         %{scid: nil},
         _runtime_identity,
         _path_templates,
         _link_assignments,
         _available,
         _mission_id
       ),
       do: []

  defp link_assignment_finding(
         spacecraft,
         nil,
         _path_templates,
         _link_assignments,
         _available,
         mission_id
       ) do
    [
      %{
        owner: :link_assignment,
        severity: :missing,
        title: "#{spacecraft.display_name} has no runtime identity",
        body: "Sync runtime identity before assigning mission-owned links to this spacecraft.",
        action_label: "Edit identity",
        action_navigate: spacecraft_identity_path(mission_id, spacecraft)
      }
    ]
  end

  defp link_assignment_finding(
         spacecraft,
         runtime_identity,
         _path_templates,
         link_assignments,
         available,
         mission_id
       ) do
    assigned_downlink? =
      Enum.any?(link_assignments, fn assignment ->
        assignment.source_endpoint_ref == runtime_identity.source_endpoint_id and
          assignment.direction == :downlink and assignment.provider_profile_refs != []
      end)

    cond do
      assigned_downlink? ->
        []

      available != [] ->
        [
          %{
            owner: :link_assignment,
            severity: :warning,
            title: "#{spacecraft.display_name} needs a downlink assignment",
            body: "Assign an available provider-backed mission downlink to this spacecraft.",
            action_label: "Assign link",
            action_navigate: spacecraft_links_path(mission_id, spacecraft)
          }
        ]

      true ->
        [
          %{
            owner: :link_assignment,
            severity: :missing,
            title: "#{spacecraft.display_name} has no provider-backed downlink available",
            body:
              "Create a shared downlink before assigning mission connectivity to this spacecraft.",
            action_label: "Create shared link",
            action_navigate: mission_link_builder_path(mission_id)
          }
        ]
    end
  end

  defp spacecraft_interpretation_findings(
         spacecraft,
         telemetry_configs_by_spacecraft,
         active_telemetry,
         mission_id
       ) do
    Enum.flat_map(spacecraft, fn spacecraft ->
      telemetry_config = Map.get(telemetry_configs_by_spacecraft, spacecraft.spacecraft_id)
      telemetry_status = TelemetryDecom.status(telemetry_config, active_telemetry)

      []
      |> add_if(is_nil(spacecraft.scid), %{
        owner: :spacecraft_interpretation,
        severity: :missing,
        title: "#{spacecraft.display_name} is missing SCID",
        body:
          "Set spacecraft identity so Cadence can recognize downlink bytes for this spacecraft.",
        action_label: "Edit identity",
        action_navigate: spacecraft_identity_path(mission_id, spacecraft)
      })
      |> Kernel.++(telemetry_interpretation_findings(spacecraft, telemetry_status, mission_id))
    end)
  end

  defp telemetry_interpretation_findings(_spacecraft, :applied, _mission_id), do: []

  defp telemetry_interpretation_findings(spacecraft, telemetry_status, mission_id) do
    [
      %{
        owner: :spacecraft_interpretation,
        severity: telemetry_finding_severity(telemetry_status),
        title:
          "#{spacecraft.display_name} telemetry interpretation #{telemetry_status_label(telemetry_status)}",
        body: telemetry_finding_body(telemetry_status),
        action_label: telemetry_action_label(telemetry_status),
        action_navigate: spacecraft_telemetry_path(mission_id, spacecraft)
      }
    ]
  end

  defp telemetry_finding_severity(:not_configured), do: :missing
  defp telemetry_finding_severity(:disabled), do: :missing
  defp telemetry_finding_severity(_status), do: :warning

  defp telemetry_status_label(:not_configured), do: "is not configured"
  defp telemetry_status_label(:configured), do: "is not applied"
  defp telemetry_status_label(:outdated), do: "is out of date"
  defp telemetry_status_label(:disabled), do: "is disabled"

  defp telemetry_finding_body(:not_configured),
    do: "Configure catalog binding and APID ownership before downlink data can be interpreted."

  defp telemetry_finding_body(:configured),
    do: "Telemetry interpretation is saved but has not been applied to the mission runtime."

  defp telemetry_finding_body(:outdated),
    do: "Telemetry interpretation has changed since the active mission runtime was applied."

  defp telemetry_finding_body(:disabled),
    do: "Telemetry interpretation is disabled for this spacecraft."

  defp telemetry_action_label(:not_configured), do: "Configure telemetry"
  defp telemetry_action_label(_status), do: "Review telemetry"

  defp active_telemetry_activation(organization_id, mission_id) do
    case Cadence.fetch_active_binding_set_activation(organization_id, mission_id) do
      {:ok, activation} ->
        %{
          binding_set_id: activation.binding_set_id,
          binding_set_version: activation.binding_set_version
        }

      {:error, _reason} ->
        nil
    end
  end

  defp spacecraft_identity_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
  end

  defp spacecraft_telemetry_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry"
  end

  defp spacecraft_links_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
  end

  defp mission_link_builder_path(mission_id) do
    ~p"/missions/#{mission_id}/comms/links/new"
  end

  defp ref_version(ref) do
    case Map.get(ref, "version") do
      version when is_integer(version) -> version
      version when is_binary(version) -> parse_ref_version(version)
      _other -> 1
    end
  end

  defp parse_ref_version(value) do
    case Integer.parse(value) do
      {version, ""} -> version
      _other -> 1
    end
  end

  defp profile_versions_by_ref(
         active_profiles,
         path_templates,
         id_key,
         list_versions,
         organization_id,
         mission_id
       ) do
    active_profiles_by_id = profile_map(active_profiles, id_key)

    path_templates
    |> profile_ref_ids(id_key)
    |> Enum.reduce(active_profiles_by_id, fn profile_id, profiles_by_id ->
      maybe_put_referenced_profile(
        profiles_by_id,
        profile_id,
        list_versions.(organization_id, mission_id, profile_id)
      )
    end)
  end

  defp maybe_put_referenced_profile(profiles_by_id, profile_id, versions) do
    if Map.has_key?(profiles_by_id, profile_id) do
      profiles_by_id
    else
      put_referenced_profile(profiles_by_id, profile_id, versions)
    end
  end

  defp put_referenced_profile(profiles_by_id, profile_id, [
         %{lifecycle_state: :deleted} = latest_profile | _versions
       ]) do
    Map.put(profiles_by_id, profile_id, {:archived, latest_profile})
  end

  defp put_referenced_profile(profiles_by_id, profile_id, [latest_profile | _versions]) do
    Map.put(profiles_by_id, profile_id, latest_profile)
  end

  defp put_referenced_profile(profiles_by_id, _profile_id, []), do: profiles_by_id

  defp profile_map(profiles, "provider_profile_id") do
    Map.new(profiles, &{&1.provider_profile_id, &1})
  end

  defp profile_map(profiles, "transport_profile_id") do
    Map.new(profiles, &{&1.transport_profile_id, &1})
  end

  defp profile_ref_ids(path_templates, id_key) do
    path_templates
    |> Enum.flat_map(&profile_refs(&1, id_key))
    |> Enum.map(&Map.get(&1, id_key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp profile_refs(path_template, "provider_profile_id"), do: path_template.provider_profile_refs

  defp profile_refs(path_template, "transport_profile_id"),
    do: path_template.transport_profile_refs

  defp selected_path_findings(_path_templates, link_assignments, source_endpoints_by_id) do
    link_assignments
    |> Enum.group_by(& &1.source_endpoint_ref)
    |> Enum.flat_map(fn {source_endpoint_ref, assignments} ->
      runtime_identity = runtime_identity_label(source_endpoint_ref, source_endpoints_by_id)

      selected_uplinks =
        Enum.filter(assignments, &(&1.direction == :uplink and &1.selection_role == :selected))

      selected_downlinks =
        Enum.filter(assignments, &(&1.direction == :downlink and &1.selection_role == :selected))

      []
      |> add_if(length(selected_uplinks) > 1, %{
        owner: :link_assignment,
        severity: :warning,
        title: "Multiple selected uplink link templates for #{runtime_identity}",
        body:
          "Uplink uniqueness is scoped to a runtime identity or realized contact, not the whole mission. Review this runtime identity's selected uplink templates."
      })
      |> add_if(assignments != [] and selected_downlinks == [], %{
        owner: :link_assignment,
        severity: :warning,
        title: "No selected downlink link template for #{runtime_identity}",
        body:
          "Downlink can have contributors, but one selected/preferred downlink link template is useful for operator summaries."
      })
    end)
  end

  defp runtime_identity_label(source_endpoint_ref, source_endpoints_by_id) do
    case Map.get(source_endpoints_by_id, source_endpoint_ref) do
      nil -> source_endpoint_ref
      source_endpoint -> source_endpoint.display_name || source_endpoint.source_endpoint_id
    end
  end

  defp add_if(findings, true, finding), do: findings ++ [finding]
  defp add_if(findings, false, _finding), do: findings

  defp finding_groups(findings) do
    findings
    |> Enum.group_by(&Map.get(&1, :owner, :mission_network))
    |> Enum.flat_map(fn {owner, findings} ->
      if findings == [] do
        []
      else
        [Map.put(finding_group(owner), :findings, findings)]
      end
    end)
    |> Enum.sort_by(& &1.order)
  end

  defp finding_group(:mission_network) do
    %{
      id: "comms-validation-mission-network",
      order: 1,
      title: "Mission Network",
      description: "Shared providers, link templates, and reusable protocol behavior."
    }
  end

  defp finding_group(:link_assignment) do
    %{
      id: "comms-validation-link-assignment",
      order: 2,
      title: "Link Assignments",
      description: "How mission-owned links attach to spacecraft runtime identities."
    }
  end

  defp finding_group(:spacecraft_interpretation) do
    %{
      id: "comms-validation-spacecraft-interpretation",
      order: 3,
      title: "Spacecraft Interpretation",
      description: "Spacecraft-owned identity, telemetry interpretation, and commanding setup."
    }
  end

  defp finding_label(:missing), do: "Blocking"
  defp finding_label(:warning), do: "Warning"
  defp finding_label(other), do: human_atom(other)
end
