defmodule CadenceWeb.CommsValidation do
  @moduledoc """
  Pure logic for computing comms-setup validation findings and grouping
  them for display. Used by `CommsOverviewLive` for the setup summary and by
  `CommsValidationLive` for the dedicated validation page.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  import CadenceWeb.CommsComponents, only: [display_name: 2, human_atom: 1]

  alias Cadence.Applications.TelemetryDecom
  alias CadenceWeb.SpacecraftCommsReadiness

  def findings_for_mission(organization_id, mission_id) do
    findings_for_resources(
      organization_id,
      mission_id,
      %{
        spacecraft: Cadence.list_spacecraft(organization_id, mission_id),
        source_endpoints: Cadence.list_source_endpoints(organization_id, mission_id),
        path_templates: Cadence.list_path_templates(organization_id, mission_id),
        provider_profiles: Cadence.list_provider_profiles(organization_id, mission_id),
        transport_profiles: Cadence.list_transport_profiles(organization_id, mission_id),
        transports: Cadence.list_transports(organization_id, mission_id),
        routing_rules: Cadence.list_routing_rules(organization_id, mission_id)
      }
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
    findings_for_resources(
      organization_id,
      mission_id,
      %{
        spacecraft: spacecraft,
        source_endpoints: source_endpoints,
        path_templates: path_templates,
        provider_profiles: provider_profiles,
        transport_profiles: transport_profiles,
        transports: Cadence.list_transports(organization_id, mission_id),
        routing_rules: Cadence.list_routing_rules(organization_id, mission_id)
      }
    )
  end

  def findings_for_resources(organization_id, mission_id, resources) when is_map(resources) do
    spacecraft = Map.fetch!(resources, :spacecraft)
    source_endpoints = Map.fetch!(resources, :source_endpoints)
    path_templates = Map.fetch!(resources, :path_templates)
    provider_profiles = Map.fetch!(resources, :provider_profiles)
    transport_profiles = Map.fetch!(resources, :transport_profiles)
    transports = Map.fetch!(resources, :transports)
    routing_rules = Map.fetch!(resources, :routing_rules)

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
    |> Kernel.++(transport_setup_findings(transports, mission_id))
    |> Kernel.++(routing_setup_findings(spacecraft, transports, routing_rules, mission_id))
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
      spacecraft_setup_findings(
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
      owner: :advanced_runtime_identity,
      severity: :blocked,
      title: "No internal telemetry identities configured",
      body:
        "Internal runtime diagnostics need telemetry identities so ingress can resolve ownership."
    })
    |> add_if(path_templates == [], %{
      owner: :advanced_runtime_identity,
      severity: :blocked,
      title: "No internal routing artifacts configured",
      body:
        "Create Routing Rules to materialize internal runtime artifacts used during execution."
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
      owner: :advanced_runtime_identity,
      severity: :attention,
      title: "No transport compatibility providers configured",
      body: "Transports materialize provider records for existing runtime integrations."
    })
    |> add_if(transport_profiles == [], %{
      owner: :advanced_runtime_identity,
      severity: :attention,
      title: "No advanced protocol behaviors configured",
      body:
        "Advanced protocol behaviors are optional runtime-local extensions such as uplink gateways and heartbeat monitors."
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
          owner: :advanced_runtime_identity,
          severity: :blocked,
          title: "#{path_name} references a missing internal telemetry identity",
          body:
            "Update the Routing Rule artifact or restore internal telemetry identity #{template.source_endpoint_ref}."
        }
      )
      |> add_if(template.provider_profile_refs == [], %{
        owner: :advanced_runtime_identity,
        severity: :blocked,
        title: "#{path_name} has no transport provider artifact",
        body:
          "The internal runtime artifact cannot connect to or receive from an external stream without a provider record."
      })
      |> add_if(template.transport_profile_refs == [], %{
        owner: :advanced_runtime_identity,
        severity: :attention,
        title: "#{path_name} has no advanced protocol behavior",
        body:
          "Advanced protocol behavior is optional unless this runtime integration needs a transport extension."
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
              owner: :advanced_runtime_identity,
              severity: :blocked,
              title: "#{path_name} references an archived #{profile_label}",
              body:
                "#{path_name} still references archived #{profile_name} v#{ref_version}. Refresh the Routing Rule artifact with an active #{profile_label}."
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
              owner: :advanced_runtime_identity,
              severity: :attention,
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
              owner: :advanced_runtime_identity,
              severity: :blocked,
              title: "#{path_name} references a missing #{profile_label}",
              body: "Refresh the Routing Rule artifact or restore #{profile_label} #{profile_id}."
            }
          )
        ]
    end
  end

  defp path_action_finding(_path_template, _mission_id, finding) do
    Map.put(finding, :owner, :advanced_runtime_identity)
  end

  defp transport_setup_findings(transports, mission_id) do
    []
    |> add_if(transports == [], %{
      owner: :transport_setup,
      severity: :blocked,
      title: "No Transports configured",
      body: "Add a Transport to describe a durable byte-moving capability for this mission.",
      action_label: "Add Transport",
      action_navigate: ~p"/missions/#{mission_id}/comms/transports/new"
    })
    |> Kernel.++(
      Enum.flat_map(transports, fn transport ->
        []
        |> add_if(is_nil(transport.materialized_provider_profile_id), %{
          owner: :advanced_runtime_identity,
          severity: :attention,
          title: "#{transport.display_name} has no runtime provider artifact",
          body:
            "This Transport is saved, but the existing runtime compatibility provider record was not materialized.",
          action_label: "Review Transport",
          action_navigate: ~p"/missions/#{mission_id}/comms/transports/#{transport.transport_id}"
        })
      end)
    )
  end

  defp routing_setup_findings(spacecraft, transports, routing_rules, mission_id) do
    transport_refs = MapSet.new(transports, & &1.transport_id)

    []
    |> add_if(spacecraft != [] and transports != [] and routing_rules == [], %{
      owner: :routing_setup,
      severity: :blocked,
      title: "No Routing Rules configured",
      body: "Create Routing Rules to declare how spacecraft use mission Transports.",
      action_label: "Create Routing Rule",
      action_navigate: ~p"/missions/#{mission_id}/comms/routing/new"
    })
    |> Kernel.++(
      Enum.flat_map(spacecraft, fn spacecraft ->
        spacecraft_routing_findings(spacecraft, routing_rules, transports, mission_id)
      end)
    )
    |> Kernel.++(
      Enum.flat_map(routing_rules, fn rule ->
        routing_rule_findings(rule, transport_refs, mission_id)
      end)
    )
  end

  defp spacecraft_routing_findings(_spacecraft, _routing_rules, [], _mission_id), do: []

  defp spacecraft_routing_findings(spacecraft, routing_rules, _transports, mission_id) do
    has_rule? = Enum.any?(routing_rules, &(&1.spacecraft_id == spacecraft.spacecraft_id))

    []
    |> add_if(not has_rule?, %{
      owner: :routing_setup,
      severity: :attention,
      title: "#{spacecraft.display_name} has no Routing Rule",
      body: "Add a Routing Rule when this spacecraft should use a mission Transport.",
      action_label: "Review Routing",
      action_navigate: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
    })
  end

  defp routing_rule_findings(rule, transport_refs, mission_id) do
    []
    |> add_if(not rule.enabled?, %{
      owner: :routing_setup,
      severity: :attention,
      title: "#{rule.display_name} is disabled",
      body: "Enable or archive this Routing Rule so the intended transport use is clear.",
      action_label: "Review Routing Rule",
      action_navigate: ~p"/missions/#{mission_id}/comms/routing/#{rule.routing_rule_id}"
    })
    |> add_if(not MapSet.member?(transport_refs, rule.transport_id), %{
      owner: :routing_setup,
      severity: :blocked,
      title: "#{rule.display_name} references an unavailable Transport",
      body: "Update the Routing Rule to use an active Transport.",
      action_label: "Review Routing Rule",
      action_navigate: ~p"/missions/#{mission_id}/comms/routing/#{rule.routing_rule_id}"
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
        owner: :advanced_runtime_identity,
        severity: :blocked,
        title: "#{spacecraft.display_name} has no internal telemetry identity",
        body: "Sync internal telemetry identity before execution can resolve this spacecraft.",
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
            owner: :advanced_runtime_identity,
            severity: :attention,
            title: "#{spacecraft.display_name} has no selected downlink runtime artifact",
            body: "Routing Rules can materialize internal runtime artifacts for execution.",
            action_label: "Review Routing",
            action_navigate: spacecraft_routing_path(mission_id, spacecraft)
          }
        ]

      true ->
        [
          %{
            owner: :advanced_runtime_identity,
            severity: :blocked,
            title:
              "#{spacecraft.display_name} has no provider-backed downlink artifact available",
            body:
              "Create a Transport and Routing Rule before reviewing internal runtime artifacts.",
            action_label: "Create Routing Rule",
            action_navigate: mission_routing_path(mission_id)
          }
        ]
    end
  end

  defp spacecraft_setup_findings(
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
        owner: :spacecraft_setup,
        severity: :blocked,
        title: "#{spacecraft.display_name} is missing SCID",
        body:
          "Set spacecraft identity so Cadence can associate interpreted bytes with this spacecraft.",
        action_label: "Edit identity",
        action_navigate: spacecraft_identity_path(mission_id, spacecraft)
      })
      |> add_if(is_nil(spacecraft.spacecraft_type_id), %{
        owner: :spacecraft_setup,
        severity: :attention,
        title: "#{spacecraft.display_name} has no Spacecraft Profile",
        body: "Select a Spacecraft Profile to pin the byte-interpretation contract.",
        action_label: "Select profile",
        action_navigate: spacecraft_identity_path(mission_id, spacecraft)
      })
      |> Kernel.++(telemetry_interpretation_findings(spacecraft, telemetry_status, mission_id))
    end)
  end

  defp telemetry_interpretation_findings(_spacecraft, :applied, _mission_id), do: []

  defp telemetry_interpretation_findings(spacecraft, telemetry_status, mission_id) do
    [
      %{
        owner: :spacecraft_setup,
        severity: telemetry_finding_severity(telemetry_status),
        title:
          "#{spacecraft.display_name} telemetry application #{telemetry_status_label(telemetry_status)}",
        body: telemetry_finding_body(telemetry_status),
        action_label: telemetry_action_label(telemetry_status),
        action_navigate: spacecraft_telemetry_path(mission_id, spacecraft)
      }
    ]
  end

  defp telemetry_finding_severity(:not_configured), do: :blocked
  defp telemetry_finding_severity(:disabled), do: :blocked
  defp telemetry_finding_severity(_status), do: :attention

  defp telemetry_status_label(:not_configured), do: "is not configured"
  defp telemetry_status_label(:configured), do: "is not applied"
  defp telemetry_status_label(:outdated), do: "is out of date"
  defp telemetry_status_label(:disabled), do: "is disabled"

  defp telemetry_finding_body(:not_configured),
    do: "Configure catalog binding and APID ownership for this spacecraft application."

  defp telemetry_finding_body(:configured),
    do: "Telemetry application setup is saved but has not been applied."

  defp telemetry_finding_body(:outdated),
    do: "Telemetry application setup has changed since it was last applied."

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

  defp spacecraft_routing_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
  end

  defp mission_routing_path(mission_id) do
    ~p"/missions/#{mission_id}/comms/routing/new"
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
      telemetry_identity = runtime_identity_label(source_endpoint_ref, source_endpoints_by_id)

      selected_uplinks =
        Enum.filter(assignments, &(&1.direction == :uplink and &1.selection_role == :selected))

      selected_downlinks =
        Enum.filter(assignments, &(&1.direction == :downlink and &1.selection_role == :selected))

      []
      |> add_if(length(selected_uplinks) > 1, %{
        owner: :advanced_runtime_identity,
        severity: :attention,
        title: "Multiple selected uplink runtime artifacts for #{telemetry_identity}",
        body:
          "Uplink uniqueness is scoped to an internal telemetry identity or realized contact, not the whole mission. Review this identity's selected uplink artifacts."
      })
      |> add_if(assignments != [] and selected_downlinks == [], %{
        owner: :advanced_runtime_identity,
        severity: :attention,
        title: "No selected downlink runtime artifact for #{telemetry_identity}",
        body:
          "Downlink can have contributors, but one selected or preferred runtime artifact is useful for operator summaries."
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

  def finding_groups(findings) do
    findings
    |> Enum.group_by(&Map.get(&1, :owner, :advanced_runtime_identity))
    |> Enum.flat_map(fn {owner, findings} ->
      if findings == [] do
        []
      else
        [Map.put(finding_group(owner), :findings, findings)]
      end
    end)
    |> Enum.sort_by(& &1.order)
  end

  defp finding_group(:spacecraft_setup) do
    %{
      id: "comms-validation-spacecraft-setup",
      order: 1,
      title: "Spacecraft Setup",
      description: "Identity, Spacecraft Profile, and application setup owned by each spacecraft."
    }
  end

  defp finding_group(:transport_setup) do
    %{
      id: "comms-validation-transport-setup",
      order: 2,
      title: "Transport Setup",
      description: "Durable byte-moving capabilities available to this mission."
    }
  end

  defp finding_group(:routing_setup) do
    %{
      id: "comms-validation-routing-setup",
      order: 3,
      title: "Routing Setup",
      description: "Durable rules for how spacecraft use mission Transports."
    }
  end

  defp finding_group(:advanced_runtime_identity) do
    %{
      id: "comms-validation-advanced-runtime-identity",
      order: 4,
      title: "Internal Runtime Artifacts",
      description:
        "Diagnostics for internal execution artifacts derived from spacecraft routing setup."
    }
  end

  def finding_label(:blocked), do: "Blocking"
  def finding_label(:attention), do: "Warning"
  def finding_label(other), do: human_atom(other)
end
