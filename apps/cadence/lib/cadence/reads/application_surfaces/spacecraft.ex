defmodule Cadence.Reads.ApplicationSurfaces.Spacecraft do
  @moduledoc "Core-owned trusted DTO provider for the federated Spacecraft application."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{
    ApplicationDefinition,
    HostContext,
    JSONBoundary,
    SurfaceQueryContribution,
    SurfaceQueryRequest,
    TelemetryDecom
  }

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.ExtensionCatalog
  alias Cadence.Missions
  alias Cadence.Reads.Applications.Inventory
  alias Cadence.Reads.Applications.InventoryItem
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore

  @application_key "spacecraft"
  @application_version 1
  @surface_version 1
  @max_map_keys 32

  @surface_queries %{
    "list" => "cadence.spacecraft.list",
    "new" => "cadence.spacecraft.new",
    "profile_list" => "cadence.spacecraft.profiles",
    "profile_new" => "cadence.spacecraft.profile.new",
    "profile_show" => "cadence.spacecraft.profile.show",
    "show" => "cadence.spacecraft.show",
    "edit" => "cadence.spacecraft.edit",
    "readiness" => "cadence.spacecraft.readiness",
    "routing" => "cadence.spacecraft.routing",
    "commanding" => "cadence.spacecraft.commanding",
    "applications" => "cadence.spacecraft.applications",
    "telemetry_decom" => "cadence.telemetry_decom.manage"
  }

  @mission_surfaces Map.keys(@surface_queries) --
                      [
                        "show",
                        "edit",
                        "readiness",
                        "routing",
                        "commanding",
                        "applications",
                        "telemetry_decom"
                      ]
  @spacecraft_surfaces Map.keys(@surface_queries) -- @mission_surfaces

  @impl true
  def application_key, do: @application_key

  @doc "Returns the authoritative provider map entries owned by Spacecraft."
  @spec contributions() :: [SurfaceQueryContribution.t()]
  def contributions do
    Enum.map(@surface_queries, fn {_surface_id, query_id} ->
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: @application_version,
        query_id: query_id,
        query_version: @surface_version,
        provider: __MODULE__
      }
    end)
    |> Enum.sort_by(& &1.query_id)
  end

  @impl true
  def load(%Scope{} = scope, %HostContext{} = host_context, %SurfaceQueryRequest{} = request) do
    guarded(fn -> load_surface(scope, host_context, request) end)
  end

  defp load_surface(
         %Scope{organization_id: organization_id, mission_id: scope_mission_id} = scope,
         %HostContext{placement: placement, mission_id: mission_id} = host_context,
         %SurfaceQueryRequest{
           application_key: @application_key,
           application_version: @application_version,
           surface_version: @surface_version,
           query_version: @surface_version,
           surface_id: surface_id,
           query_id: query_id,
           params: params
         }
       )
       when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
              mission_id != "" and is_map(params) and placement in [:mission, :spacecraft] and
              (is_nil(scope_mission_id) or scope_mission_id == mission_id) do
    with :ok <- validate_surface_scope(surface_id, placement),
         :ok <- validate_query_identity(surface_id, query_id),
         :ok <- validate_params(surface_id, params),
         :ok <- authorize(scope, mission_id),
         {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         :ok <- ensure_mission_scope(mission, organization_id, mission_id),
         {:ok, data} <- dispatch_surface(scope, host_context, mission, surface_id, params),
         {:ok, safe_data} <- JSONBoundary.safe(data) do
      {:ok,
       %{
         "navigation" => navigation(surface_id, mission_id, host_context),
         "data" => safe_data
       }}
    end
  end

  defp load_surface(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp dispatch_surface(_scope, host_context, mission, "list", params),
    do: list_presentation(mission, host_context, params)

  defp dispatch_surface(_scope, _host_context, mission, "new", _params),
    do: {:ok, new_presentation(mission)}

  defp dispatch_surface(_scope, _host_context, mission, "profile_list", _params),
    do: {:ok, profile_list_presentation(mission)}

  defp dispatch_surface(_scope, _host_context, mission, "profile_new", _params),
    do: {:ok, profile_new_presentation(mission)}

  defp dispatch_surface(_scope, _host_context, mission, "profile_show", params),
    do: profile_show_presentation(mission, params)

  defp dispatch_surface(scope, host_context, mission, "show", _params),
    do: spacecraft_presentation(scope, host_context, mission, :show)

  defp dispatch_surface(scope, host_context, mission, "edit", _params),
    do: spacecraft_presentation(scope, host_context, mission, :edit)

  defp dispatch_surface(scope, host_context, mission, "readiness", _params),
    do: spacecraft_presentation(scope, host_context, mission, :readiness)

  defp dispatch_surface(scope, host_context, mission, "routing", _params),
    do: routing_presentation(scope, host_context, mission)

  defp dispatch_surface(_scope, host_context, mission, "commanding", _params),
    do: commanding_presentation(host_context, mission)

  defp dispatch_surface(scope, host_context, mission, "applications", _params),
    do: applications_presentation(scope, host_context, mission)

  defp dispatch_surface(scope, host_context, mission, "telemetry_decom", _params),
    do: telemetry_decom_presentation(scope, host_context, mission)

  defp dispatch_surface(_scope, _host_context, _mission, _surface_id, _params),
    do: {:error, :unsupported_application_surface_query}

  defp list_presentation(mission, _host_context, params) do
    search = Map.get(params, "q", "")
    page_number = positive_integer(Map.get(params, "page"), 1)
    sort = if Map.get(params, "sort") == "display_name", do: :display_name, else: :scid
    direction = if Map.get(params, "dir") == "desc", do: :desc, else: :asc

    page =
      SpacecraftStore.list_spacecraft_page(mission.organization_id, mission.mission_id,
        search: search,
        sort: {sort, direction},
        page: page_number,
        page_size: 50
      )

    types = SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)
    summary = SpacecraftStore.fleet_summary(mission.organization_id, mission.mission_id)
    latest_versions = Map.new(types, &{&1.spacecraft_type_id, &1.version})

    drift_count =
      Enum.count(summary.profile_version_counts, fn count ->
        latest_versions[count.spacecraft_type_id] != count.spacecraft_type_version
      end)

    {:ok,
     %{
       "presentation" => %{
         "root" => %{"attrs" => %{"id" => "spacecraft-management-page", "class" => "space-y-6"}},
         "header" =>
           header("Spacecraft", "Manage spacecraft identities and their pinned profiles."),
         "breadcrumbs" => breadcrumbs(mission, "Spacecraft", spacecraft_path(mission, nil)),
         "summary_tiles" => summary_tiles(mission, summary, drift_count, params),
         "roster" => roster(mission, page, summary),
         "profiles" =>
           profile_preview(mission, types, summary.profile_version_counts, latest_versions)
       }
     }}
  end

  defp new_presentation(mission) do
    types = SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)

    %{
      "page" => %{
        "id" => "spacecraft-new-page",
        "heading" => "New Spacecraft",
        "subtitle" =>
          "Register a spacecraft for this mission. Optionally select a profile to pin its byte-interpretation contract.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb("New Spacecraft", nil)
        ]
      },
      "form" => spacecraft_form("new", nil, types),
      "profile_options" => profile_options(types, true)
    }
  end

  defp profile_list_presentation(mission) do
    profiles =
      SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)

    %{
      "presentation" => %{
        "root" => %{"attrs" => %{"id" => "spacecraft-profiles-page", "class" => "space-y-6"}},
        "header" => profile_header(mission, length(profiles)),
        "empty_state" =>
          if(profiles == [],
            do:
              empty_state(
                "No Spacecraft Profiles",
                "Define a profile before registering a spacecraft."
              ),
            else: nil
          ),
        "card" => if(profiles == [], do: nil, else: profile_card(mission, profiles))
      }
    }
  end

  defp profile_new_presentation(mission) do
    definitions = ExtensionCatalog.available_applications_for_scope(:mission)

    %{
      "page" => %{
        "id" => "spacecraft-profile-new-page",
        "title" => "New Spacecraft Profile",
        "subtitle" =>
          "Captures the byte-interpretation contract shared across spacecraft of the same kind — downlink and uplink protocols, frame parameters, and which platform applications run.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb("Profiles", profiles_path(mission)),
          breadcrumb("New Spacecraft Profile", nil)
        ]
      },
      "form" => profile_form(mission),
      "options" => profile_form_options(),
      "applications" => Enum.map(definitions, &application_option/1)
    }
  end

  defp profile_show_presentation(mission, params) do
    with {:ok, profile_id} <- required_id(params, "profile_id"),
         {:ok, profile} <-
           SpacecraftTypeStore.fetch_spacecraft_type(
             mission.organization_id,
             mission.mission_id,
             profile_id
           ) do
      versions =
        SpacecraftTypeStore.list_spacecraft_type_versions(
          mission.organization_id,
          mission.mission_id,
          profile_id
        )

      {:ok,
       %{
         "profile" => profile_details(profile),
         "navigation" => %{
           "breadcrumbs" => [
             navigation_item(mission.display_name, mission_path(mission)),
             navigation_item("Spacecraft", spacecraft_path(mission, nil)),
             navigation_item("Profiles", profiles_path(mission)),
             navigation_item(profile.display_name, nil)
           ]
         },
         "labels" => %{
           "byte_interpretation" => "Byte Interpretation",
           "applications" => "Applications",
           "version_history" => "Version History",
           "frame_parameters" => "Frame Parameters",
           "no_applications" => "No applications declared."
         },
         "versions" => Enum.map(versions, &version_details/1)
       }}
    end
  end

  defp spacecraft_presentation(scope, host_context, mission, mode) do
    with {:ok, spacecraft} <- fetch_host_spacecraft(mission, host_context),
         {:ok, profile} <- pinned_profile(mission, spacecraft) do
      case mode do
        :show ->
          {:ok, spacecraft_show(scope, host_context, mission, spacecraft, profile)}

        :edit ->
          {:ok, spacecraft_edit(mission, spacecraft)}

        :readiness ->
          {:ok, spacecraft_readiness(scope, host_context, mission, spacecraft, profile)}
      end
    end
  end

  defp spacecraft_edit(mission, spacecraft) do
    types = SpacecraftTypeStore.list_spacecraft_types(mission.organization_id, mission.mission_id)

    %{
      "page" => %{
        "id" => "spacecraft-edit-page",
        "heading" => "Spacecraft Identity",
        "subtitle" =>
          "Update the durable identity and profile binding for #{spacecraft.display_name}.",
        "breadcrumbs" => [
          breadcrumb(mission.display_name, mission_path(mission)),
          breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
          breadcrumb(spacecraft.display_name, spacecraft_path(mission, spacecraft.spacecraft_id)),
          breadcrumb("Identity", nil)
        ]
      },
      "form" => spacecraft_form("edit", spacecraft, types),
      "profile_options" => profile_options(types, false)
    }
  end

  defp spacecraft_show(scope, host_context, mission, spacecraft, profile) do
    applications = declared_inventory(scope, host_context, profile_declarations(profile))
    app_summary = Inventory.summary(applications)
    href = spacecraft_path(mission, spacecraft.spacecraft_id)

    %{
      "page" => %{
        "id" => "spacecraft-show-page",
        "header" => %{
          "title" => spacecraft.display_name,
          "breadcrumbs" => [
            navigation_item(mission.display_name, mission_path(mission)),
            navigation_item("Spacecraft", spacecraft_path(mission, nil)),
            navigation_item(spacecraft.display_name, nil)
          ],
          "title_suffix" =>
            if(spacecraft.scid,
              do: %{"set" => true, "label" => "SCID #{spacecraft.scid}"},
              else: %{"set" => false, "label" => "SCID not set"}
            )
        }
      },
      "profile_binding" => profile_binding(mission, spacecraft, profile),
      "applications" =>
        application_inventory(mission, spacecraft, profile, applications, app_summary),
      "workflow_cards" => workflow_cards(mission, spacecraft, profile, app_summary),
      "overview" => overview(spacecraft, mission)
    }
    |> Map.put("_fallback_href", href)
    |> Map.delete("_fallback_href")
  end

  defp spacecraft_readiness(scope, host_context, mission, spacecraft, profile) do
    applications = declared_inventory(scope, host_context, profile_declarations(profile))
    summary = Inventory.summary(applications)

    identity_status =
      if is_integer(spacecraft.scid),
        do: status("ready", "Ready"),
        else: status("attention", "Attention")

    profile_status =
      if profile, do: status("ready", "Current"), else: status("attention", "Unbound")

    {:ok,
     %{
       "page" => %{
         "id" => "spacecraft-readiness-page",
         "title" => "Readiness",
         "title_suffix" => "· #{spacecraft.display_name}",
         "subtitle" =>
           "A bounded view of the identity, profile, applications, and routing setup required for operations.",
         "breadcrumbs" => [
           breadcrumb(mission.display_name, mission_path(mission)),
           breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
           breadcrumb(
             spacecraft.display_name,
             spacecraft_path(mission, spacecraft.spacecraft_id)
           ),
           breadcrumb("Readiness", nil)
         ],
         "status" =>
           status(
             if(identity_status["tone"] == "ready" and profile_status["tone"] == "ready",
               do: "ready",
               else: "attention"
             ),
             "Review setup"
           )
       },
       "panels" => [
         readiness_panel(
           "spacecraft-readiness-identity",
           "Identity",
           identity_status,
           "Durable spacecraft identity.",
           [%{"label" => "SCID", "value" => scid_label(spacecraft)}],
           "Edit Identity",
           identity_path(mission, spacecraft)
         ),
         readiness_panel(
           "spacecraft-readiness-profile",
           "Profile",
           profile_status,
           "Pinned byte-interpretation contract.",
           [
             %{
               "label" => "Pinned Profile",
               "value" => (profile && profile.display_name) || "None"
             }
           ],
           if(profile, do: "Change Profile", else: "Select Profile"),
           identity_path(mission, spacecraft)
         ),
         readiness_panel(
           "spacecraft-readiness-applications",
           "Applications",
           status(to_string(summary.tone), summary.label),
           "Profile-declared applications and their installation state.",
           [],
           "Review Applications",
           applications_path(mission, spacecraft),
           %{
             "id" => "spacecraft-readiness-application-list",
             "empty_state" => %{
               "id" => "spacecraft-readiness-application-empty",
               "description" => "No applications are declared by the pinned profile."
             }
           }
         ),
         readiness_panel(
           "spacecraft-readiness-routing",
           "Routing",
           status("info", "Tracked in Comms"),
           "Routing rules are maintained in the Comms setup area.",
           [%{"label" => "Setup Area", "value" => "Routing Rules"}],
           "Review Routing",
           routing_path(mission, spacecraft)
         )
       ],
       "applications" => Enum.map(applications, &readiness_application/1)
     }}
  end

  defp routing_presentation(_scope, host_context, mission) do
    with {:ok, spacecraft} <- fetch_host_spacecraft(mission, host_context) do
      rules =
        RoutingRuleStore.list_routing_rules_for_spacecraft(
          mission.organization_id,
          mission.mission_id,
          spacecraft.spacecraft_id
        )

      transports =
        Map.new(
          TransportStore.list_transports(mission.organization_id, mission.mission_id),
          &{&1.transport_id, &1}
        )

      {:ok,
       %{
         "page" => %{
           "title" => "Comms Routing",
           "subtitle" =>
             "Durable routing rules that describe how this spacecraft uses mission transports.",
           "breadcrumbs" => [
             breadcrumb(mission.display_name, mission_path(mission)),
             breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
             breadcrumb(
               spacecraft.display_name,
               spacecraft_path(mission, spacecraft.spacecraft_id)
             ),
             breadcrumb("Routing", nil)
           ],
           "new_rule" => %{
             "id" => "new-spacecraft-routing-rule-link",
             "label" => "New Routing Rule",
             "href" =>
               "#{mission_path(mission)}/comms/routing/new?spacecraft_id=#{spacecraft.spacecraft_id}"
           },
           "empty_state" => %{
             "title" => "No routing rules",
             "description" =>
               "Create a routing rule when this spacecraft should use a mission transport."
           },
           "rules_id" => "spacecraft-routing-rules",
           "rows" => Enum.map(rules, &routing_row(&1, transports, mission))
         }
       }}
    end
  end

  defp commanding_presentation(host_context, mission) do
    spacecraft_id = host_context.spacecraft_id

    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             mission.organization_id,
             mission.mission_id,
             spacecraft_id
           ) do
      {:ok,
       %{
         "page" => %{
           "id" => "spacecraft-commanding-page",
           "title" => "Commanding for #{spacecraft.display_name}",
           "subtitle" =>
             "Command interpretation and uplink framing will be configured from the pinned spacecraft profile.",
           "eyebrow" => "Command Interpretation",
           "breadcrumbs" => [
             breadcrumb(mission.display_name, mission_path(mission)),
             breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
             breadcrumb(
               spacecraft.display_name,
               spacecraft_path(mission, spacecraft.spacecraft_id)
             ),
             breadcrumb("Commanding", nil)
           ],
           "status" => status("info", "Not tracked")
         },
         "panels" =>
           Enum.map(
             [
               {"spacecraft-commanding-encoding", "Encoding",
                "Command encoding is not tracked yet."},
               {"spacecraft-commanding-tc-framing", "TC Framing",
                "Telecommand framing is not tracked yet."},
               {"spacecraft-commanding-uplink", "Uplink",
                "Uplink transport behavior is not tracked yet."}
             ],
             fn {id, title, description} ->
               %{
                 "id" => id,
                 "title" => title,
                 "value" => "Not tracked",
                 "status" => status("info", "Setup"),
                 "description" => description
               }
             end
           ),
         "readiness" => %{
           "eyebrow" => "Readiness Impact",
           "title" => "Command interpretation is not part of readiness yet",
           "description" =>
             "This surface remains an explicit local boundary until command interpretation has a durable host contract.",
           "status" => status("info", "Placeholder")
         }
       }}
    end
  end

  defp applications_presentation(scope, host_context, mission) do
    with {:ok, spacecraft} <- fetch_host_spacecraft(mission, host_context),
         {:ok, profile} <- pinned_profile(mission, spacecraft) do
      items = declared_inventory(scope, host_context, profile_declarations(profile))

      {:ok,
       %{"presentation" => applications_presentation_dto(mission, spacecraft, profile, items)}}
    end
  end

  defp applications_presentation_dto(mission, spacecraft, profile, items) do
    %{
      "root" => %{
        "attrs" => %{"id" => "spacecraft-applications-page", "class" => "space-y-6"}
      },
      "header" => %{
        "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
        "body" => %{"attrs" => %{}},
        "content" => %{"attrs" => %{}},
        "breadcrumbs" => %{
          "attrs" => %{"class" => "flex items-center gap-2 text-xs text-base-content/60"},
          "items" => [
            breadcrumb(mission.display_name, mission_path(mission)),
            breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
            breadcrumb(
              spacecraft.display_name,
              spacecraft_path(mission, spacecraft.spacecraft_id)
            ),
            breadcrumb("Applications", nil)
          ]
        },
        "title" => %{"attrs" => %{}, "text" => "Applications"},
        "subtitle" => %{
          "attrs" => %{"class" => "mt-1 text-sm text-base-content/70"},
          "text" => "Manage the applications declared by the pinned spacecraft profile."
        },
        "actions" => %{
          "attrs" => %{},
          "readiness" => %{
            "attrs" => %{"href" => readiness_path(mission, spacecraft)},
            "text" => "Readiness"
          }
        }
      },
      "component" => %{"attrs" => %{"id" => "spacecraft-applications-component"}},
      "profile" => applications_profile(mission, spacecraft, profile),
      "applications" => Enum.map(items, &application_card(&1, mission, spacecraft))
    }
  end

  defp applications_profile(_mission, _spacecraft, nil),
    do: %{
      "kind" => "missing",
      "id" => "spacecraft-applications-no-profile",
      "label" => "Spacecraft Profile",
      "title" => "No profile selected",
      "description" =>
        "Select a Spacecraft Profile before installing profile-declared applications.",
      "action" => %{"label" => "Select profile", "path" => "#"}
    }

  defp applications_profile(_mission, _spacecraft, profile),
    do: %{
      "kind" => "pinned",
      "id" => "spacecraft-applications-profile",
      "label" => "Pinned Profile",
      "display_name" => profile.display_name,
      "version" => profile.version,
      "status" => %{"tone" => "ready", "label" => "Current"}
    }

  defp application_card(%InventoryItem{} = item, mission, spacecraft) do
    card_id = "spacecraft-application-#{safe_key(item.application_key)}"

    %{
      "id" => card_id,
      "application_key" => item.application_key,
      "application_version" => item.application_version,
      "display_name" => item.display_name,
      "description" => item.description,
      "lifecycle_state" => item.lifecycle_state && to_string(item.lifecycle_state),
      "installable" => item.installable?,
      "manageable" => item.manageable?,
      "uninstallable" => item.uninstallable?,
      "scope_label" => "Application",
      "manage_path" => "#{applications_path(mission, spacecraft)}/#{item.application_key}",
      "status" => %{
        "state" => to_string(item.status.state),
        "label" => item.status.label,
        "tone" => to_string(item.status.tone),
        "facts" =>
          Enum.map(item.status.facts, fn fact ->
            %{"id" => fact.id, "label" => fact.label, "value" => fact.value}
          end)
      },
      "install_action" =>
        if(item.installable? and not item.manageable?,
          do: lifecycle_action("#{card_id}-install", "install", "Install", "primary"),
          else: nil
        ),
      "disable_action" =>
        if(item.manageable?,
          do: lifecycle_action("#{card_id}-disable", "disable", "Disable", "secondary"),
          else: nil
        ),
      "uninstall_action" =>
        if(item.uninstallable?,
          do: lifecycle_action("#{card_id}-uninstall", "uninstall", "Uninstall", "danger"),
          else: nil
        ),
      "unavailable_message" =>
        if(item.installable?,
          do: nil,
          else: "This application is not available at the spacecraft scope."
        )
    }
  end

  defp telemetry_decom_presentation(scope, host_context, mission) do
    with {:ok, spacecraft} <- fetch_host_spacecraft(mission, host_context),
         revisions <- Catalog.list_revisions(mission.organization_id, mission.mission_id),
         {:ok, config} <- optional_config(mission, spacecraft) do
      selected = config && config.catalog_revision_id

      revision =
        Enum.find(revisions, &(&1.catalog_revision_id == selected)) || List.first(revisions)

      status_value = TelemetryDecom.status(config, nil)

      {:ok,
       %{
         "page" => %{
           "id" => "spacecraft-telemetry-decom-page",
           "title" => "Telemetry Decom",
           "subtitle" =>
             "Application packet inputs and publication state for #{spacecraft.display_name}.",
           "breadcrumbs" => [
             breadcrumb(mission.display_name, mission_path(mission)),
             breadcrumb("Spacecraft", spacecraft_path(mission, nil)),
             breadcrumb(
               spacecraft.display_name,
               spacecraft_path(mission, spacecraft.spacecraft_id)
             ),
             breadcrumb("Applications", applications_path(mission, spacecraft)),
             breadcrumb("Telemetry Decom", nil)
           ]
         },
         "card" => %{"id" => "telemetry-decom-card"},
         "status" => telemetry_status(status_value, config),
         "revision" => revision_dto(revisions, revision),
         "no_revisions" =>
           if(revisions == [],
             do: %{
               "message" => "Import a catalog revision before configuring Telemetry Decom.",
               "action" => %{
                 "id" => "telemetry-decom-open-catalog",
                 "label" => "Open Catalog",
                 "href" => "#{mission_path(mission)}/catalog"
               }
             },
             else: nil
           ),
         "packet_handoff" => packet_handoff(spacecraft, config, revision, mission),
         "preview" => telemetry_preview(scope, mission, config),
         "preflight" => telemetry_preflight(scope, host_context, mission),
         "pending_activation" => nil,
         "lifecycle_actions" => telemetry_actions(config)
       }}
    end
  end

  defp telemetry_preview(_scope, _mission, nil), do: nil

  defp telemetry_preview(_scope, _mission, _config),
    do: %{
      "id" => "telemetry-decom-preview",
      "label" => "Preview",
      "empty_message" =>
        "Select one or more packet APIDs to preview the application input binding.",
      "stats" => [],
      "diagnostics" => nil
    }

  defp telemetry_preflight(_scope, _host_context, _mission),
    do: %{
      "id" => "telemetry-decom-preflight",
      "state" => "attention",
      "activation_ready" => false,
      "check_count" => 0,
      "application_version" => 1,
      "summary" => "Activation readiness is evaluated by the host when requested.",
      "label" => "Review",
      "checks_id" => "telemetry-decom-preflight-checks",
      "checks" => []
    }

  defp telemetry_actions(config) do
    %{
      "disable" =>
        if(config && config.enabled,
          do: lifecycle_action("telemetry-decom-disable", "disable", "Disable", "secondary"),
          else: nil
        ),
      "empty_message" => nil
    }
  end

  defp revision_dto([], _revision), do: nil

  defp revision_dto(revisions, revision) do
    %{
      "form_id" => "telemetry-decom-revision-form",
      "field" => %{
        "id" => "telemetry-decom-revision-select",
        "name" => "catalog_revision_id",
        "label" => "Catalog revision",
        "value" => (revision && revision.catalog_revision_id) || "",
        "options" =>
          Enum.map(
            revisions,
            &%{
              "label" => "#{&1.revision_label} (v#{&1.revision_number})",
              "value" => &1.catalog_revision_id
            }
          )
      },
      "action" => %{"id" => "telemetry-decom-save-revision", "label" => "Use revision"}
    }
  end

  defp packet_handoff(_spacecraft, _config, nil, _mission), do: nil

  defp packet_handoff(spacecraft, config, _revision, mission) do
    selected = (config && length(config.handled_apids)) || 0

    %{
      "id" => "telemetry-decom-packet-handoff",
      "label" => "Packet inputs",
      "selection_count" => selected,
      "row_count" => selected,
      "summary_suffix" => "selected",
      "detail" => "APID selection is managed by the packet binding surface.",
      "action" => %{
        "id" => "telemetry-decom-open-packet-bindings",
        "label" => "Open packet bindings",
        "href" => "#{applications_path(mission, spacecraft)}/telemetry_decom/packet_bindings"
      }
    }
  end

  defp optional_config(mission, spacecraft) do
    case TelemetryDecom.fetch_config(
           mission.organization_id,
           mission.mission_id,
           spacecraft.spacecraft_id
         ) do
      {:ok, config} -> {:ok, config}
      {:error, :not_configured} -> {:ok, nil}
    end
  end

  defp profile_declarations(nil), do: %{}
  defp profile_declarations(%SpacecraftType{applications: applications}), do: applications

  defp declared_inventory(scope, host_context, declarations) do
    definitions = ExtensionCatalog.applications_for_scope(host_context.placement)

    case Inventory.declared(scope, host_context, declarations, definitions) do
      {:ok, items} -> items
      {:error, _reason} -> []
    end
  end

  defp fetch_host_spacecraft(mission, %HostContext{
         placement: :spacecraft,
         spacecraft_id: spacecraft_id
       }) do
    SpacecraftStore.fetch_spacecraft(mission.organization_id, mission.mission_id, spacecraft_id)
  end

  defp pinned_profile(_mission, %SpacecraftAsset{spacecraft_type_id: nil}), do: {:ok, nil}

  defp pinned_profile(mission, %SpacecraftAsset{
         spacecraft_type_id: type_id,
         spacecraft_type_version: version
       })
       when is_binary(type_id) and is_integer(version) do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           mission.organization_id,
           mission.mission_id,
           type_id,
           version
         ) do
      {:ok, profile} -> {:ok, profile}
      {:error, _reason} -> {:ok, nil}
    end
  end

  defp pinned_profile(_mission, _spacecraft), do: {:ok, nil}

  defp validate_surface_scope(surface_id, :mission) when surface_id in @mission_surfaces, do: :ok

  defp validate_surface_scope(surface_id, :spacecraft) when surface_id in @spacecraft_surfaces,
    do: :ok

  defp validate_surface_scope(_surface_id, _placement),
    do: {:error, :unsupported_application_host_context}

  defp validate_query_identity(surface_id, query_id) do
    if Map.get(@surface_queries, surface_id) == query_id,
      do: :ok,
      else: {:error, :unsupported_application_surface_query}
  end

  defp validate_params("list", params) do
    validate_param_keys(params, ~w(q sort dir page pageSize filter))
  end

  defp validate_params("profile_show", params), do: validate_param_keys(params, ["profile_id"])
  defp validate_params(_surface_id, params), do: validate_param_keys(params, [])

  defp validate_param_keys(params, allowed) do
    keys = Map.keys(params)

    cond do
      length(keys) > @max_map_keys -> {:error, :application_surface_bounds_exceeded}
      not Enum.all?(keys, &is_binary/1) -> {:error, :invalid_application_request}
      MapSet.subset?(MapSet.new(keys), MapSet.new(allowed)) -> :ok
      true -> {:error, :invalid_application_request}
    end
  end

  defp required_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :invalid_application_request}
    end
  end

  defp authorize(scope, mission_id),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission_id
      })

  defp ensure_mission_scope(
         %{organization_id: organization_id, mission_id: mission_id},
         organization_id,
         mission_id
       ),
       do: :ok

  defp ensure_mission_scope(_mission, _organization_id, _mission_id),
    do: {:error, :unsupported_application_surface_query}

  defp navigation(surface_id, mission_id, %HostContext{placement: :mission}) do
    %{
      "fallback_href" => "#{mission_path_id(mission_id)}/spacecraft",
      "breadcrumbs" => [
        %{"label" => "Mission", "href" => mission_path_id(mission_id)},
        %{"label" => surface_label(surface_id), "href" => nil}
      ]
    }
  end

  defp navigation(surface_id, mission_id, %HostContext{
         placement: :spacecraft,
         spacecraft_id: spacecraft_id
       }) do
    %{
      "fallback_href" =>
        "#{mission_path_id(mission_id)}/spacecraft/#{spacecraft_id}/#{surface_id}",
      "breadcrumbs" => [
        %{"label" => "Mission", "href" => mission_path_id(mission_id)},
        %{"label" => "Spacecraft", "href" => "#{mission_path_id(mission_id)}/spacecraft"},
        %{"label" => surface_label(surface_id), "href" => nil}
      ]
    }
  end

  defp mission_path_id(mission_id), do: "/missions/#{mission_id}"

  defp surface_label("list"), do: "Spacecraft"
  defp surface_label("new"), do: "New Spacecraft"
  defp surface_label("profile_list"), do: "Profiles"
  defp surface_label("profile_new"), do: "New Profile"
  defp surface_label("profile_show"), do: "Profile"
  defp surface_label("show"), do: "Overview"
  defp surface_label("edit"), do: "Identity"
  defp surface_label("readiness"), do: "Readiness"
  defp surface_label("routing"), do: "Routing"
  defp surface_label("commanding"), do: "Commanding"
  defp surface_label("applications"), do: "Applications"
  defp surface_label("telemetry_decom"), do: "Telemetry Decom"

  defp trusted_url(value), do: to_string(value)

  defp mission_path(mission), do: "/missions/#{trusted_url(mission.mission_id)}"
  defp spacecraft_path(mission, nil), do: "#{mission_path(mission)}/spacecraft"
  defp spacecraft_path(mission, id), do: "#{mission_path(mission)}/spacecraft/#{trusted_url(id)}"
  defp profiles_path(mission), do: "#{spacecraft_path(mission, nil)}/profiles"
  defp profile_path(mission, id), do: "#{profiles_path(mission)}/#{trusted_url(id)}"

  defp identity_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/identity"

  defp readiness_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/readiness"

  defp routing_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/routing"

  defp applications_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/applications"

  defp breadcrumb(label, href), do: %{"label" => label, "href" => href}
  defp navigation_item(label, href), do: breadcrumb(label, href)

  defp header(title, subtitle),
    do: %{
      "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
      "body" => %{"attrs" => %{}},
      "content" => %{"attrs" => %{}},
      "title" => %{
        "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
        "text" => title
      },
      "subtitle" => %{
        "attrs" => %{"class" => "mt-1 text-sm text-base-content/70"},
        "text" => subtitle
      }
    }

  defp breadcrumbs(mission, label, href),
    do: %{
      "attrs" => %{"class" => "flex items-center gap-2 text-xs text-base-content/60"},
      "items" => [
        breadcrumb(mission.display_name, mission_path(mission)),
        breadcrumb(label, href)
      ]
    }

  defp summary_tiles(mission, summary, drift_count, params) do
    filter = Map.get(params, "filter")

    [
      tile(
        "spacecraft-tile-all",
        "All spacecraft",
        summary.total,
        spacecraft_path(mission, nil),
        is_nil(filter),
        false
      ),
      tile(
        "spacecraft-tile-missing-scid",
        "Missing SCID",
        summary.missing_scid,
        "#{spacecraft_path(mission, nil)}?filter=missing_scid",
        filter == "missing_scid",
        summary.missing_scid > 0
      ),
      tile(
        "spacecraft-tile-missing-profile",
        "Missing profile",
        summary.missing_profile,
        "#{spacecraft_path(mission, nil)}?filter=missing_profile",
        filter == "missing_profile",
        summary.missing_profile > 0
      ),
      tile(
        "spacecraft-tile-drift",
        "Profile drift",
        drift_count,
        spacecraft_path(mission, nil),
        false,
        drift_count > 0
      )
    ]
  end

  defp tile(id, label, value, href, active, warning),
    do: %{
      "id" => id,
      "label" => label,
      "value" => value,
      "href" => href,
      "active" => active,
      "warning" => warning
    }

  defp roster(mission, page, summary) do
    %{
      "fleet_empty" => summary.total == 0,
      "subtitle" => "#{summary.total} total · #{summary.missing_profile} missing profile",
      "new_spacecraft_href" => "#{spacecraft_path(mission, nil)}/new",
      "search" => "",
      "sort_by" => "scid",
      "sort_dir" => "asc",
      "filtered_empty" => page.items == [],
      "page" => page.page,
      "page_size" => page.page_size,
      "total_count" => page.total_count,
      "pagination_visible" => page.total_count > page.page_size,
      "range_label" => range_label(page),
      "previous_page" => max(page.page - 1, 1),
      "next_page" => page.page + 1,
      "previous_disabled" => page.page <= 1,
      "next_disabled" => page.page * page.page_size >= page.total_count,
      "rows" => Enum.map(page.items, &spacecraft_row(&1, mission))
    }
  end

  defp range_label(%{total_count: 0}), do: "0 spacecraft"

  defp range_label(page),
    do:
      "#{(page.page - 1) * page.page_size + 1}–#{min(page.page * page.page_size, page.total_count)} of #{page.total_count}"

  defp spacecraft_row(spacecraft, mission) do
    profile_label =
      if spacecraft.spacecraft_type_id, do: spacecraft.spacecraft_type_id, else: "Not set"

    ready? = is_integer(spacecraft.scid) and not is_nil(spacecraft.spacecraft_type_id)

    %{
      "id" => "spacecraft-#{spacecraft.spacecraft_id}",
      "actions_id" => "#{spacecraft.spacecraft_id}-actions",
      "display_name" => spacecraft.display_name,
      "scid_label" => scid_label(spacecraft),
      "scid_missing" => is_nil(spacecraft.scid),
      "profile_label" => profile_label,
      "status" => if(ready?, do: "ready", else: "attention"),
      "status_label" => if(ready?, do: "Ready", else: "Attention"),
      "href" => spacecraft_path(mission, spacecraft.spacecraft_id),
      "identity_href" => identity_path(mission, spacecraft)
    }
  end

  defp profile_preview(mission, profiles, counts, latest) do
    rows =
      profiles
      |> Enum.take(5)
      |> Enum.map(fn profile ->
        %{
          "id" => "spacecraft-profile-preview-#{profile.spacecraft_type_id}",
          "display_name" => profile.display_name,
          "href" => profile_path(mission, profile.spacecraft_type_id),
          "fleet_entries" => fleet_entries(profile, counts, latest, mission),
          "protocols" =>
            "#{String.upcase(to_string(profile.downlink_protocol))} / #{String.upcase(to_string(profile.uplink_protocol))}",
          "applications" => application_summary(profile.applications),
          "status" => "ready",
          "status_label" => "Current"
        }
      end)

    %{
      "empty" => profiles == [],
      "truncated" => length(profiles) > 5,
      "subtitle" => "#{length(profiles)} total",
      "new_profile_href" => "#{profiles_path(mission)}/new",
      "all_profiles_href" => profiles_path(mission),
      "rows" => rows
    }
  end

  defp fleet_entries(profile, counts, latest, mission) do
    counts
    |> Enum.filter(&(&1.spacecraft_type_id == profile.spacecraft_type_id))
    |> Enum.map(fn count ->
      %{
        "label" => "v#{count.spacecraft_type_version} × #{count.count}",
        "href" =>
          if(count.spacecraft_type_version != Map.get(latest, profile.spacecraft_type_id),
            do: spacecraft_path(mission, nil),
            else: nil
          )
      }
    end)
  end

  defp application_summary(applications),
    do: applications |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &humanize/1)

  defp profile_header(mission, count),
    do:
      Map.merge(
        header("Spacecraft Profiles", "#{count} defined profiles shared across spacecraft."),
        %{
          "actions" => %{
            "attrs" => %{},
            "new_profile" => %{
              "id" => "new-spacecraft-profile-link",
              "label" => "New Profile",
              "href" => "#{profiles_path(mission)}/new"
            }
          }
        }
      )

  defp empty_state(title, description), do: %{"title" => title, "description" => description}

  defp profile_card(mission, profiles),
    do: %{
      "attrs" => %{
        "id" => "spacecraft-profiles-card",
        "class" => "card border border-base-300 bg-base-200"
      },
      "body" => %{"attrs" => %{"class" => "card-body p-0"}},
      "list_component" => %{"attrs" => %{"id" => "spacecraft-profiles-list-component"}},
      "rows" =>
        Enum.map(
          profiles,
          &%{
            "id" => "spacecraft-profile-#{&1.spacecraft_type_id}",
            "display_name" => &1.display_name,
            "version" => "v#{&1.version}",
            "downlink_protocol" => String.upcase(to_string(&1.downlink_protocol)),
            "uplink_protocol" => String.upcase(to_string(&1.uplink_protocol)),
            "applications" => application_summary(&1.applications),
            "href" => profile_path(mission, &1.spacecraft_type_id)
          }
        )
    }

  defp spacecraft_form(kind, spacecraft, _types) do
    %{
      "id" => spacecraft_form_id(kind),
      "sections" => %{
        "identity" => %{
          "id" => identity_section_id(kind),
          "number" => "01",
          "title" => "Identity"
        },
        "profile" => %{
          "id" => profile_section_id(kind),
          "number" => "02",
          "title" => "Profile"
        }
      },
      "fields" => %{
        "display_name" =>
          field(
            display_name_field_id(kind),
            "spacecraft[display_name]",
            "text",
            "Display Name",
            (spacecraft && spacecraft.display_name) || "",
            true
          ),
        "scid" =>
          field(
            scid_field_id(kind),
            "spacecraft[scid]",
            "text",
            "SCID",
            scid_value(spacecraft),
            false
          ),
        "spacecraft_type_id" =>
          field(
            profile_field_id(kind),
            "spacecraft[spacecraft_type_id]",
            "select",
            "Spacecraft Profile",
            (spacecraft && spacecraft.spacecraft_type_id) || "",
            false
          )
      },
      "actions" => %{
        "submit" => %{
          "id" => submit_button_id(kind),
          "label" => submit_button_label(kind)
        },
        "cancel" => %{
          "id" => cancel_link_id(kind),
          "label" => "Cancel",
          "href" => ""
        }
      }
    }
  end

  defp spacecraft_form_id("edit"), do: "spacecraft-edit-form"
  defp spacecraft_form_id(_kind), do: "spacecraft-form"

  defp identity_section_id("edit"), do: "spacecraft-edit-identity-section"
  defp identity_section_id(_kind), do: "spacecraft-identity-section"

  defp profile_section_id("edit"), do: "spacecraft-edit-profile-section"
  defp profile_section_id(_kind), do: "spacecraft-profile-section"

  defp display_name_field_id("edit"), do: "spacecraft-edit-display-name"
  defp display_name_field_id(_kind), do: "spacecraft-display-name"

  defp scid_field_id("edit"), do: "spacecraft-edit-scid"
  defp scid_field_id(_kind), do: "spacecraft-scid"

  defp profile_field_id("edit"), do: "spacecraft-edit-profile"
  defp profile_field_id(_kind), do: "spacecraft-profile"

  defp submit_button_id("edit"), do: "save-spacecraft-identity-button"
  defp submit_button_id(_kind), do: "create-spacecraft-button"

  defp submit_button_label("edit"), do: "Save Identity"
  defp submit_button_label(_kind), do: "Create Spacecraft"

  defp cancel_link_id("edit"), do: "cancel-spacecraft-identity-link"
  defp cancel_link_id(_kind), do: "cancel-spacecraft-link"

  defp field(id, name, type, label, value, required),
    do: %{
      "id" => id,
      "name" => name,
      "type" => type,
      "label" => label,
      "value" => value,
      "required" => required
    }

  defp profile_options(types, include_empty),
    do: %{
      "options" =>
        if(include_empty, do: [%{"label" => "None", "value" => ""}], else: []) ++
          Enum.map(
            types,
            &%{"label" => "#{&1.display_name} (v#{&1.version})", "value" => &1.spacecraft_type_id}
          ),
      "empty" => types == [],
      "empty_state" => %{
        "message" => "No spacecraft profiles are defined.",
        "action" => %{
          "id" => "create-spacecraft-profile-link",
          "label" => "Create one",
          "href" => "profiles/new"
        },
        "suffix" => ""
      }
    }

  defp profile_form(_mission) do
    %{
      "id" => "spacecraft-profile-form",
      "sections" => %{
        "identity" => section("spacecraft-profile-identity-section", "01", "Identity", nil),
        "protocols" => section("spacecraft-profile-protocols-section", "02", "Protocols", nil),
        "frame_parameters" =>
          section(
            "spacecraft-profile-frame-parameters-section",
            "03",
            "Frame Parameters",
            "How the spacecraft frames the bytes it transmits. Fields adapt to the selected downlink protocol."
          ),
        "applications" =>
          section("spacecraft-profile-applications-section", "04", "Applications", nil)
      },
      "fields" => %{
        "display_name" =>
          field(
            "spacecraft-profile-display-name",
            "spacecraft_type[display_name]",
            "text",
            "Display Name",
            "",
            true
          ),
        "downlink_protocol" =>
          field(
            "spacecraft-profile-downlink-protocol",
            "spacecraft_type[downlink_protocol]",
            "select",
            "Downlink Protocol",
            "tm",
            true
          ),
        "uplink_protocol" =>
          field(
            "spacecraft-profile-uplink-protocol",
            "spacecraft_type[uplink_protocol]",
            "select",
            "Uplink Protocol",
            "tc",
            true
          ),
        "frame_size" =>
          field(
            "spacecraft-profile-frame-size",
            "spacecraft_type[frame_size]",
            "number",
            "Transfer Frame Size (bytes)",
            "",
            true
          ),
        "secondary_header_length" =>
          field(
            "spacecraft-profile-secondary-header-length",
            "spacecraft_type[secondary_header_length]",
            "number",
            "Secondary Header Length (bytes, 0 if absent)",
            "0",
            false
          ),
        "insert_zone_length" =>
          field(
            "spacecraft-profile-insert-zone-length",
            "spacecraft_type[insert_zone_length]",
            "number",
            "Insert Zone Length (bytes, 0 if absent)",
            "0",
            false
          ),
        "truncated_primary_header" =>
          field(
            "spacecraft-profile-truncated-primary-header",
            "spacecraft_type[truncated_primary_header]",
            "select",
            "Truncated Primary Header",
            "false",
            false
          ),
        "ocf_length" =>
          field(
            "spacecraft-profile-ocf-length",
            "spacecraft_type[ocf_length]",
            "select",
            "Operational Control Field",
            "0",
            false
          ),
        "applications" => %{
          "id" => "spacecraft-profile-application-options",
          "name" => "spacecraft_type[applications]",
          "value" => %{}
        }
      },
      "actions" => %{
        "submit" => %{"id" => "create-spacecraft-profile-button", "label" => "Create Profile"},
        "cancel" => %{
          "id" => "cancel-spacecraft-profile-link",
          "label" => "Cancel",
          "href" => "profiles"
        }
      }
    }
  end

  defp section(id, number, title, description),
    do: %{"id" => id, "number" => number, "title" => title, "description" => description}

  defp profile_form_options,
    do: %{
      "downlink_protocols" => [
        %{"label" => "TM", "value" => "tm"},
        %{"label" => "AOS", "value" => "aos"},
        %{"label" => "USLP", "value" => "uslp"}
      ],
      "uplink_protocols" => [
        %{"label" => "TC", "value" => "tc"},
        %{"label" => "USLP", "value" => "uslp"}
      ],
      "truncated_primary_headers" => [
        %{"label" => "No", "value" => "false"},
        %{"label" => "Yes", "value" => "true"}
      ],
      "operational_control_fields" => [
        %{"label" => "Not present", "value" => "0"},
        %{"label" => "Present (4 bytes)", "value" => "4"}
      ],
      "frame_fields" => %{
        "secondary_header_length" => ["tm"],
        "insert_zone_length" => ["aos"],
        "truncated_primary_header" => ["uslp"]
      }
    }

  defp application_option(%ApplicationDefinition{} = definition),
    do: %{
      "id" => "spacecraft-profile-application-#{definition.application_key}",
      "key" => definition.application_key,
      "name" => "spacecraft_type[applications][#{definition.application_key}]",
      "value" => "1",
      "label" => definition.display_name,
      "description" => definition.description,
      "available" => ApplicationDefinition.available?(definition),
      "availability_label" =>
        if(ApplicationDefinition.available?(definition), do: nil, else: "Roadmap")
    }

  defp profile_details(profile),
    do: %{
      "id" => "spacecraft-profile-#{profile.spacecraft_type_id}",
      "profile_id" => profile.spacecraft_type_id,
      "display_name" => profile.display_name,
      "version" => "v#{profile.version}",
      "lifecycle" => to_string(profile.lifecycle_state),
      "downlink_protocol" => String.upcase(to_string(profile.downlink_protocol)),
      "uplink_protocol" => String.upcase(to_string(profile.uplink_protocol)),
      "packet_protocol" => to_string(profile.packet_protocol),
      "frame_parameters" =>
        Enum.map(
          Enum.sort_by(profile.frame_parameters, fn {key, _} -> to_string(key) end),
          fn {key, value} ->
            %{
              "id" => "spacecraft-profile-frame-parameter-#{key}",
              "label" => humanize(key),
              "value" => to_string(value)
            }
          end
        ),
      "applications" =>
        Enum.map(Enum.sort(Map.keys(profile.applications)), fn key ->
          %{"id" => "spacecraft-profile-application-#{key}", "label" => humanize(key)}
        end)
    }

  defp version_details(profile),
    do: %{
      "id" => "spacecraft-profile-version-#{profile.spacecraft_type_id}-#{profile.version}",
      "version" => "v#{profile.version}",
      "lifecycle" => to_string(profile.lifecycle_state),
      "downlink_protocol" => String.upcase(to_string(profile.downlink_protocol)),
      "uplink_protocol" => String.upcase(to_string(profile.uplink_protocol))
    }

  defp profile_binding(mission, _spacecraft, nil),
    do: %{
      "id" => "spacecraft-profile-binding",
      "eyebrow" => "Spacecraft Profile",
      "bound" => false,
      "title" => "No profile selected",
      "description" => "Select a Spacecraft Profile to define the byte-interpretation contract.",
      "version" => nil,
      "protocols" => [],
      "status" => status("attention", "Unbound"),
      "view_profile_href" => nil,
      "profile_action" => %{
        "label" => "Select profile",
        "href" => "#{mission_path(mission)}/spacecraft"
      }
    }

  defp profile_binding(mission, spacecraft, profile),
    do: %{
      "id" => "spacecraft-profile-binding",
      "eyebrow" => "Pinned Profile",
      "bound" => true,
      "title" => profile.display_name,
      "description" => nil,
      "version" => "v#{profile.version}",
      "protocols" => [
        %{"label" => "Downlink", "value" => to_string(profile.downlink_protocol)},
        %{"label" => "Uplink", "value" => to_string(profile.uplink_protocol)}
      ],
      "status" => status("ready", "Current"),
      "view_profile_href" => profile_path(mission, profile.spacecraft_type_id),
      "profile_action" => %{
        "label" => "Change profile",
        "href" => identity_path(mission, spacecraft)
      }
    }

  defp application_inventory(mission, spacecraft, nil, _items, _summary),
    do: %{
      "id" => "spacecraft-applications",
      "list_id" => "spacecraft-applications-list",
      "visible" => true,
      "title" => "Applications",
      "description" => "Select a Spacecraft Profile before managing applications.",
      "empty" => true,
      "empty_state" => "No applications are declared.",
      "rows" => [],
      "view_action" => %{
        "label" => "View applications",
        "href" => applications_path(mission, spacecraft)
      }
    }

  defp application_inventory(mission, spacecraft, _profile, items, summary),
    do: %{
      "id" => "spacecraft-applications",
      "list_id" => "spacecraft-applications-list",
      "visible" => true,
      "title" => "Applications",
      "description" => "Profile-declared applications for this spacecraft.",
      "empty" => items == [],
      "empty_state" => "No applications are declared by the pinned profile.",
      "rows" => Enum.map(items, &application_row(&1, mission, spacecraft)),
      "view_action" => %{
        "label" => "View applications",
        "href" => applications_path(mission, spacecraft)
      },
      "summary" => summary.label
    }

  defp application_row(%InventoryItem{} = item, mission, spacecraft),
    do: %{
      "id" => "spacecraft-application-#{safe_key(item.application_key)}",
      "application_key" => item.application_key,
      "display_name" => item.display_name,
      "status" => status(to_string(item.status.tone), item.status.label),
      "manage_href" =>
        if(item.manageable?,
          do: "#{applications_path(mission, spacecraft)}/#{item.application_key}",
          else: nil
        )
    }

  defp workflow_cards(mission, spacecraft, profile, summary),
    do: [
      %{
        "id" => "spacecraft-workflow-identity",
        "title" => "Identity",
        "value" => if(spacecraft.scid, do: "SCID #{spacecraft.scid}", else: "SCID not set"),
        "description" => "Durable spacecraft identity and profile binding.",
        "status" =>
          status(
            if(spacecraft.scid, do: "ready", else: "attention"),
            if(spacecraft.scid, do: "Ready", else: "Attention")
          ),
        "action" => %{"label" => "Edit identity", "href" => identity_path(mission, spacecraft)}
      },
      %{
        "id" => "spacecraft-workflow-applications",
        "title" => "Applications",
        "value" => summary.label,
        "description" => "Profile-declared applications and lifecycle state.",
        "status" => status(to_string(summary.tone), summary.label),
        "action" => %{
          "label" => "Manage applications",
          "href" => applications_path(mission, spacecraft)
        }
      },
      %{
        "id" => "spacecraft-workflow-readiness",
        "title" => "Readiness",
        "value" => if(profile, do: "Profile bound", else: "Setup needed"),
        "description" => "Review the operational setup before commanding.",
        "status" =>
          status(
            if(profile, do: "ready", else: "attention"),
            if(profile, do: "Ready", else: "Review")
          ),
        "action" => %{
          "label" => "Review readiness",
          "href" => readiness_path(mission, spacecraft)
        }
      }
    ]

  defp overview(spacecraft, mission),
    do: %{
      "title" => "Overview",
      "scid" => %{"label" => "SCID", "value" => scid_label(spacecraft)},
      "display_name" => %{"label" => "Display Name", "value" => spacecraft.display_name},
      "spacecraft_id" => %{"label" => "Spacecraft ID", "value" => spacecraft.spacecraft_id},
      "mission" => %{
        "label" => "Mission",
        "value" => mission.display_name,
        "href" => mission_path(mission)
      },
      "organization_id" => %{"label" => "Organization ID", "value" => mission.organization_id},
      "metadata_json" =>
        if(spacecraft.metadata == %{},
          do: nil,
          else: Jason.encode!(spacecraft.metadata, pretty: true)
        )
    }

  defp readiness_panel(
         id,
         title,
         status,
         description,
         details,
         action_label,
         action_href,
         application_list \\ nil
       ),
       do: %{
         "id" => id,
         "title" => title,
         "status" => status,
         "description" => description,
         "details" => details,
         "action" => %{"label" => action_label, "href" => action_href},
         "application_list" => application_list
       }

  defp readiness_application(%InventoryItem{} = item),
    do: %{
      "id" => "spacecraft-readiness-application-#{safe_key(item.application_key)}",
      "application_key" => item.application_key,
      "display_name" => item.display_name,
      "status" => status(to_string(item.status.tone), item.status.label)
    }

  defp routing_row(rule, transports, mission),
    do: %{
      "id" => "spacecraft-routing-rule-#{rule.routing_rule_id}",
      "purpose_label" => rule.purpose_label,
      "display_name" => rule.display_name,
      "direction" => String.upcase(String.replace(to_string(rule.direction), "_", " ")),
      "transport_name" =>
        (Map.get(transports, rule.transport_id) &&
           Map.get(transports[rule.transport_id], :display_name)) || rule.transport_id,
      "role" => String.upcase(to_string(rule.role)),
      "state" => if(rule.enabled?, do: "ENABLED", else: "DISABLED"),
      "href" => "#{mission_path(mission)}/comms/routing/#{rule.routing_rule_id}"
    }

  defp status(tone, label) when tone in ["ready", "attention", "blocked", "info"],
    do: %{"tone" => tone, "label" => label}

  defp status(_tone, label), do: %{"tone" => "info", "label" => label}

  defp telemetry_status(state, config),
    do: %{
      "state" => to_string(state),
      "tone" => if(config && config.enabled, do: "ready", else: "attention"),
      "label" => humanize(state),
      "description" => "Telemetry Decom configuration and publication state.",
      "saved_label" => config && "v#{config.configuration_version}"
    }

  defp lifecycle_action(id, action_id, label, variant),
    do: %{
      "id" => id,
      "action_id" => action_id,
      "label" => label,
      "variant" => variant,
      "effect" => "durable",
      "execution" => "immediate",
      "confirmation" => nil
    }

  defp scid_label(%SpacecraftAsset{scid: nil}), do: "Not set"
  defp scid_label(%SpacecraftAsset{scid: scid}), do: to_string(scid)
  defp scid_value(nil), do: ""

  defp scid_value(spacecraft),
    do: scid_label(spacecraft) |> then(&if(&1 == "Not set", do: "", else: &1))

  defp humanize(value),
    do:
      value
      |> to_string()
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp safe_key(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]+/, "-")

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp guarded(fun) do
    fun.()
  rescue
    _exception -> {:error, :unsupported_application_surface_query}
  catch
    :throw, :invalid_application_request -> {:error, :invalid_application_request}
    _kind, _value -> {:error, :unsupported_application_surface_query}
  end
end
