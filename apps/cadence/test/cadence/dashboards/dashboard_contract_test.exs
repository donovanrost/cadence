defmodule Cadence.Dashboards.DashboardContractTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    Annotation,
    AnnotationSpan,
    DashboardAction,
    DashboardContract,
    DashboardResolveRequest,
    DashboardResolveResult,
    DataContext,
    DataLink,
    Engine,
    EvidenceRef,
    Field,
    Frame,
    LimitContext,
    PlacementFrames,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    ScopeContext,
    SourceFacts,
    SourceResult,
    TimeContext
  }

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.Limits.Event
  alias Cadence.Telemetry.Sample

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "validates a dashboard engine request boundary" do
    document = load_fixture!("value_tile_latest.v1.json")

    request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      document_mode: :published,
      resolve_mode: :context_change,
      time_context: %{mode: "archive", to: ~U[2026-06-17 12:00:00Z]},
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      data_context: %{realm: "flight"},
      limit_context: %{semantics_mode: "observed"},
      interaction_context: %{placement_sizes: %{"placement_battery_voltage" => %{width_px: 400}}}
    }

    assert :ok = DashboardContract.validate_request(request)
    assert :ok = Dashboards.validate_dashboard_request(request)
  end

  test "normalizes external request maps into a typed engine boundary" do
    document = load_fixture!("value_tile_latest.v1.json")

    request =
      DashboardResolveRequest.new(%{
        "organization_id" => document.organization_id,
        "mission_id" => document.mission_id,
        "dashboard_id" => document.dashboard_id,
        "document" => document,
        "document_mode" => "published",
        "resolve_mode" => "live-tick",
        "time_context" => %{"mode" => "archive", "axis" => "receipt_time"},
        "scope_context" => %{
          "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc_001"]}
        },
        "data_context" => %{
          "realm" => "rehearsal",
          "source_contexts" => %{"telemetry" => %{"data_source_id" => "rehearsal-tsdb"}}
        },
        "limit_context" => %{"semantics_mode" => "observed"},
        "interaction_context" => %{"placement_sizes" => %{"placement_battery_voltage" => %{}}}
      })

    assert %DashboardResolveRequest{
             document_mode: :published,
             resolve_mode: :live_tick,
             time_context: %TimeContext{mode: "archive", axis: "receipt_time"},
             scope_context: %ScopeContext{
               primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}
             },
             data_context: %DataContext{
               realm: "rehearsal",
               source_contexts: %{telemetry: %{data_source_id: "rehearsal-tsdb"}}
             },
             limit_context: %LimitContext{semantics_mode: "observed"}
           } = request

    assert :ok = DashboardContract.validate_request(request)
  end

  test "validates planned source requests emitted by the engine planner" do
    request =
      PlannedSourceRequest.new(%{
        "request_id" => "source-request-1",
        "organization_id" => "org-dashboards",
        "mission_id" => "mission-dashboards",
        "logical_source" => "telemetry",
        "observables" => ["tlm.hk.battery_voltage"],
        "scope_context" => %{
          "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc_001"]}
        },
        "time_context" => %{"mode" => "archive", "axis" => "receipt_time"},
        "data_context" => %{"realm" => "flight"},
        "limit_context" => %{"semantics_mode" => "observed"},
        "value_type" => "engineering",
        "sampling" => %{"mode" => "latest", "target_points" => 1},
        "source_dependencies" => [
          %{
            "logical_source" => "telemetry",
            "reason" => "limit_latest_sample_input",
            "products" => ["latest_sample"],
            "sampling" => %{"mode" => "latest"}
          }
        ],
        "overlays" => ["limits"],
        "consumers" => [
          %{
            "placement_id" => "placement-battery",
            "role" => "primary",
            "widget_type_id" => "cadence.value_tile"
          }
        ],
        "metadata" => %{"capability_provenance" => %{"binding_id" => "flight-telemetry"}}
      })

    assert %PlannedSourceRequest{
             logical_source: :telemetry,
             value_type: :engineering,
             scope_context: %ScopeContext{},
             time_context: %TimeContext{},
             data_context: %DataContext{},
             limit_context: %LimitContext{},
             source_dependencies: [
               %{
                 logical_source: :telemetry,
                 reason: :limit_latest_sample_input,
                 products: [:latest_sample],
                 sampling: %{"mode" => "latest"}
               }
             ],
             overlays: [:limits],
             consumers: [%{role: :primary}]
           } = request

    assert :ok = DashboardContract.validate_planned_source_request(request)
    assert :ok = Dashboards.validate_dashboard_planned_source_request(request)
  end

  test "reports invalid planned source request contract values" do
    request = %PlannedSourceRequest{
      request_id: "",
      organization_id: "",
      mission_id: nil,
      logical_source: :bad_source,
      observables: ["", :bad_observable],
      scope_context: "bad-scope",
      value_type: :calibrated,
      sampling: "bad-sampling",
      source_dependencies: [
        %{logical_source: :bad_source, reason: nil, products: ["bad-product"], sampling: "bad"},
        "bad-dependency"
      ],
      overlays: "bad-overlays",
      consumers: [
        %{placement_id: "", role: nil, widget_type_id: nil},
        "bad-consumer"
      ],
      metadata: "bad-metadata"
    }

    assert {:error, errors} = DashboardContract.validate_planned_source_request(request)

    assert violation?(errors, [:request_id], :invalid_binary)
    assert violation?(errors, [:organization_id], :invalid_binary)
    assert violation?(errors, [:mission_id], :invalid_binary)
    assert violation?(errors, [:logical_source], :unsupported_value)
    assert violation?(errors, [:observables, 0], :invalid_binary)
    assert violation?(errors, [:observables, 1], :invalid_binary)
    assert violation?(errors, [:scope_context], :invalid_struct)
    assert violation?(errors, [:value_type], :unsupported_value)
    assert violation?(errors, [:sampling], :invalid_map)
    assert violation?(errors, [:source_dependencies, 0, :logical_source], :unsupported_value)
    assert violation?(errors, [:source_dependencies, 0, :reason], :invalid_atom)
    assert violation?(errors, [:source_dependencies, 0, :products, 0], :invalid_atom)
    assert violation?(errors, [:source_dependencies, 0, :sampling], :invalid_map)
    assert violation?(errors, [:source_dependencies, 1], :invalid_source_dependency)
    assert violation?(errors, [:overlays], :invalid_list)
    assert violation?(errors, [:consumers, 0, :placement_id], :invalid_binary)
    assert violation?(errors, [:consumers, 0, :role], :invalid_atom)
    assert violation?(errors, [:consumers, 0, :widget_type_id], :invalid_binary)
    assert violation?(errors, [:consumers, 1], :invalid_consumer)
    assert violation?(errors, [:metadata], :invalid_map)
  end

  test "validates source capabilities used by planning" do
    capabilities =
      SourceCapabilities.new(%{
        logical_source: :telemetry,
        supported_sampling: [:latest, :bounded_history],
        supported_products: [:latest_value],
        supported_time_axes: [:receipt_time],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:scalar, :wide],
        supports_watermarks?: true,
        completeness: :partial,
        metadata: %{storage: :questdb}
      })

    assert :ok = DashboardContract.validate_source_capabilities(capabilities)
    assert :ok = Dashboards.validate_dashboard_source_capabilities(capabilities)
  end

  test "reports invalid source capability contract values" do
    capabilities = %SourceCapabilities{
      logical_source: :unknown_source,
      supported_sampling: [:latest, "not-an-atom"],
      supported_time_axes: [:generation_time, :bad_axis],
      supported_value_types: [:engineering, :calibrated],
      supported_shapes: [:scalar, :bad_shape],
      supports_watermarks?: "yes",
      completeness: :complete,
      metadata: "invalid"
    }

    assert {:error, errors} = DashboardContract.validate_source_capabilities(capabilities)

    assert violation?(errors, [:logical_source], :unsupported_value)
    assert violation?(errors, [:supported_sampling, 1], :invalid_atom)
    assert violation?(errors, [:supported_time_axes, 1], :unsupported_value)
    assert violation?(errors, [:supported_value_types, 1], :unsupported_value)
    assert violation?(errors, [:supported_shapes, 1], :unsupported_value)
    assert violation?(errors, [:supports_watermarks?], :invalid_boolean)
    assert violation?(errors, [:completeness], :unsupported_value)
    assert violation?(errors, [:metadata], :invalid_map)
  end

  test "validates source facts used by source result cache keys" do
    facts =
      SourceFacts.new(%{
        watermark: %{
          logical_source: "telemetry",
          request_id: "source-request-1",
          confidence: "unknown",
          freshness_state: "fresh"
        },
        watermarks: [
          %{
            logical_source: "telemetry",
            request_id: "source-request-1",
            confidence: "best-effort",
            freshness_state: "stale"
          }
        ],
        source_binding_segments: [%{dataset: "flight"}],
        source_health: "degraded",
        meta: %{source_health_reason: :stale}
      })

    assert :ok = DashboardContract.validate_source_facts(facts)
    assert :ok = Dashboards.validate_dashboard_source_facts(facts)
  end

  test "reports invalid source facts contract values" do
    facts = %SourceFacts{
      watermark: "invalid-watermark",
      watermarks: [
        %SourceWatermark{logical_source: :bad_source, confidence: :bad_confidence}
      ],
      source_binding_segments: [%{dataset: "flight"}, "bad-segment"],
      source_health: :offline,
      meta: "invalid"
    }

    assert {:error, errors} = DashboardContract.validate_source_facts(facts)

    assert violation?(errors, [:watermark], :invalid_watermark)
    assert violation?(errors, [:watermarks, 0, :logical_source], :unsupported_value)
    assert violation?(errors, [:watermarks, 0, :confidence], :unsupported_value)
    assert violation?(errors, [:source_binding_segments, 1], :invalid_map)
    assert violation?(errors, [:source_health], :unsupported_value)
    assert violation?(errors, [:meta], :invalid_map)
  end

  test "validates source results returned by adapters" do
    result =
      SourceResult.new(%{
        request_id: "source-request-1",
        frames: [
          %{
            source: "telemetry",
            shape: "scalar",
            fields: [
              %{
                name: "battery_voltage",
                kind: "number",
                values: [28.4],
                metadata: %{
                  evidence: [
                    %{
                      kind: "telemetry_sample",
                      id: "sample-1",
                      source: "telemetry",
                      confidence: "direct"
                    }
                  ]
                }
              }
            ],
            meta: %{
              links: [
                %{
                  link_id: "link-sample-1",
                  label: "Open sample",
                  target: "telemetry_sample",
                  target_id: "sample-1",
                  presentation: "side_panel",
                  source: "frame"
                }
              ]
            }
          }
        ],
        annotations: [
          %{
            annotation_id: "contacts:contact-1",
            provider_id: "cadence.contacts",
            layer_id: "mission-contacts",
            kind: "contact_interval",
            title: "DSS-14 pass",
            span: %{
              kind: "interval",
              starts_at: "2026-06-17T12:01:00Z",
              ends_at: "2026-06-17T12:05:00Z"
            },
            style: %{primitive: "rail", color: "cyan"},
            link: %{
              link_id: "contact:contact-1",
              label: "Open contact",
              target: "contact",
              target_id: "contact-1",
              source: "annotation"
            }
          }
        ],
        warnings: [
          %{
            code: "watermark_unknown",
            severity: "info",
            scope: "placement",
            details: %{
              actions: [
                %{
                  action_id: "action-refresh",
                  label: "Open telemetry",
                  target: "telemetry_explore",
                  kind: "invoke",
                  presentation: "button",
                  source: "warning"
                }
              ]
            }
          }
        ],
        watermarks: [
          %{
            logical_source: "telemetry",
            confidence: "best_effort",
            freshness_state: "fresh"
          }
        ],
        meta: %{source_binding_id: "binding-flight"}
      })

    assert :ok = DashboardContract.validate_source_result(result)
    assert :ok = Dashboards.validate_dashboard_source_result(result)
  end

  test "reports invalid source result contract values" do
    result = %SourceResult{
      request_id: "",
      frames: [
        %Frame{
          source: :unknown_source,
          shape: :bad_shape,
          fields: [%Field{name: nil, kind: :bad_kind, values: :not_a_list}]
        },
        "bad-frame"
      ],
      warnings: [
        %ResolveWarning{code: nil, severity: :bad_severity, scope: :bad_scope},
        "bad-warning"
      ],
      annotations: [
        %Annotation{
          annotation_id: "",
          provider_id: "",
          layer_id: "",
          title: "",
          span: %AnnotationSpan{kind: :interval, starts_at: nil, ends_at: nil},
          severity: :unknown,
          style: "invalid",
          scope: "invalid",
          provenance: "invalid",
          metadata: "invalid",
          link: "invalid"
        },
        "bad-annotation"
      ],
      watermarks: [%SourceWatermark{logical_source: :bad_source, confidence: :bad_confidence}],
      meta: "invalid"
    }

    assert {:error, errors} = DashboardContract.validate_source_result(result)

    assert violation?(errors, [:request_id], :invalid_binary)
    assert violation?(errors, [:frames, 0, :source], :unsupported_value)
    assert violation?(errors, [:frames, 0, :shape], :unsupported_value)
    assert violation?(errors, [:frames, 0, :fields, 0, :name], :invalid_binary)
    assert violation?(errors, [:frames, 0, :fields, 0, :kind], :unsupported_value)
    assert violation?(errors, [:frames, 0, :fields, 0, :values], :invalid_list)
    assert violation?(errors, [:frames, 1], :invalid_frame)
    assert violation?(errors, [:warnings, 0, :code], :invalid_atom)
    assert violation?(errors, [:warnings, 0, :severity], :unsupported_value)
    assert violation?(errors, [:warnings, 0, :scope], :unsupported_value)
    assert violation?(errors, [:warnings, 1], :invalid_warning)
    assert violation?(errors, [:annotations, 0, :annotation_id], :invalid_binary)
    assert violation?(errors, [:annotations, 0, :provider_id], :invalid_binary)
    assert violation?(errors, [:annotations, 0, :layer_id], :invalid_binary)
    assert violation?(errors, [:annotations, 0, :span], :invalid_annotation_span)
    assert violation?(errors, [:annotations, 0, :severity], :unsupported_value)
    assert violation?(errors, [:annotations, 0, :link], :invalid_data_link)
    assert violation?(errors, [:annotations, 1], :invalid_annotation)
    assert violation?(errors, [:watermarks, 0, :logical_source], :unsupported_value)
    assert violation?(errors, [:watermarks, 0, :confidence], :unsupported_value)
    assert violation?(errors, [:meta], :invalid_map)
  end

  test "request normalization preserves unsupported runtime context values for placement warnings" do
    document = load_fixture!("value_tile_latest.v1.json")

    request =
      DashboardResolveRequest.new(%{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        scope_context: %{primary: %{kind: "antenna", mode: "one", ids: ["gs-1"]}},
        data_context: %{realm: "customer-prod"},
        limit_context: %{semantics_mode: "hypothetical"}
      })

    assert %ScopeContext{primary: %{kind: "antenna"}} = request.scope_context
    assert %DataContext{realm: "customer-prod"} = request.data_context
    assert %LimitContext{semantics_mode: "hypothetical"} = request.limit_context
    assert :ok = DashboardContract.validate_request(request)
  end

  test "plan result satisfies the stable engine contract" do
    document = load_fixture!("value_tile_latest.v1.json")
    request = resolve_request(document)

    result = Engine.plan(request, validate_dashboard_contract?: true)

    assert :ok = DashboardContract.validate_plan_result(result)
    assert :ok = Dashboards.validate_dashboard_plan_result(result)

    assert Map.take(result.plan_metadata, [
             :cache,
             :time,
             :snapshot?,
             :live_append_eligible?,
             :source_request_count,
             :unbatched_source_request_count,
             :batched_consumer_count,
             :degraded?
           ])

    assert result.plan_metadata.cache.plan_cache.status in [:hit, :miss, :disabled]
  end

  test "normalizes external result maps into a typed engine boundary" do
    telemetry_frame = %Frame{
      source: :telemetry,
      shape: :scalar,
      fields: [%Field{name: "value", kind: :number, values: [12.25]}]
    }

    result =
      DashboardResolveResult.new(%{
        "dashboard_id" => "dashboard-result",
        "resolve_mode" => "context-change",
        "frames_by_placement" => %{
          "placement-value" => %{
            "primary" => [telemetry_frame],
            "overlays" => %{"limits" => []},
            "warnings" => [
              %{
                "code" => "watermark_unknown",
                "severity" => "info",
                "scope" => "placement",
                "placement_id" => "placement-value",
                "details" => %{"reason" => "source did not return watermark"},
                "evidence" => [
                  %{
                    "kind" => "source_request",
                    "id" => "source-request-telemetry",
                    "source" => "telemetry",
                    "confidence" => "direct"
                  }
                ],
                "links" => [
                  %{
                    "link_id" => "telemetry-point:HK.counter",
                    "label" => "Telemetry point",
                    "target" => "telemetry_point",
                    "target_id" => "HK.counter",
                    "presentation" => "side_panel",
                    "source" => "warning"
                  }
                ]
              }
            ],
            "planned_request_ids" => ["source-request-telemetry"]
          }
        },
        "dashboard_warnings" => [],
        "watermarks" => [
          %{
            "logical_source" => "telemetry",
            "request_id" => "source-request-telemetry",
            "confidence" => "unknown",
            "freshness_state" => "unknown"
          }
        ],
        "planned_source_requests" => [
          %{
            "request_id" => "source-request-telemetry",
            "organization_id" => "org_dashboards",
            "mission_id" => "mission_dashboards",
            "logical_source" => "telemetry",
            "observables" => ["HK.counter"],
            "scope_context" => %{
              "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc_001"]}
            },
            "time_context" => %{"mode" => "live"},
            "data_context" => %{"realm" => "flight"},
            "limit_context" => %{"semantics_mode" => "observed"},
            "sampling" => %{"mode" => "latest"},
            "overlays" => ["limits"],
            "consumers" => [
              %{
                "placement_id" => "placement-value",
                "role" => "primary",
                "widget_type_id" => "value_tile"
              }
            ]
          }
        ],
        "plan_metadata" => valid_plan_metadata()
      })

    assert %DashboardResolveResult{
             resolve_mode: :context_change,
             frames_by_placement: %{
               "placement-value" => %PlacementFrames{
                 overlays: %{limits: []},
                 warnings: [
                   %ResolveWarning{
                     code: :watermark_unknown,
                     severity: :info,
                     scope: :placement,
                     evidence: [%EvidenceRef{kind: :source_request, source: :telemetry}],
                     links: [%DataLink{target: :telemetry_point, source: :warning}]
                   }
                 ]
               }
             },
             watermarks: [%SourceWatermark{logical_source: :telemetry, confidence: :unknown}],
             planned_source_requests: [
               %PlannedSourceRequest{
                 logical_source: :telemetry,
                 scope_context: %ScopeContext{},
                 time_context: %TimeContext{},
                 data_context: %DataContext{},
                 limit_context: %LimitContext{},
                 overlays: [:limits],
                 consumers: [%{role: :primary}]
               }
             ]
           } = result

    assert :ok = DashboardContract.validate_plan_result(result)
  end

  test "resolve result satisfies execution metadata, evidence, watermark, and cache contracts" do
    document = load_fixture!("value_tile_latest.v1.json")
    parent = self()

    telemetry_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_latest, organization_id, mission_id, point_id, opts})
      telemetry_sample(mission_id, point_id)
    end

    limits_latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:limits_latest, organization_id, mission_id, point_id, opts})
      limit_event(mission_id, point_id)
    end

    result =
      Engine.resolve(resolve_request(document),
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun],
          limits: [
            latest_fun: limits_latest_fun,
            watermark_fun: fn _organization_id, _mission_id, _point_id, _opts ->
              best_effort_watermark(~U[2026-06-17 12:00:01Z])
            end
          ]
        },
        freshness_now: ~U[2026-06-17 12:00:02Z],
        validate_dashboard_contract?: true
      )

    assert :ok = DashboardContract.validate_resolve_result(result)
    assert :ok = Dashboards.validate_dashboard_resolve_result(result)

    assert result.plan_metadata.source_request_count ==
             result.plan_metadata.executed_source_request_count +
               result.plan_metadata.skipped_source_request_count

    assert is_map(result.plan_metadata.cache.source_result_keys_by_request_id)
    assert is_map(result.plan_metadata.cache.source_result_cache_by_request_id)
    assert is_map(result.plan_metadata.cache.frame_keys_by_placement)
    assert is_map(result.plan_metadata.cache.frame_cache_by_placement)

    assert Enum.any?(result.watermarks, &(&1.logical_source == :limits))
    assert Enum.any?(result.watermarks, &(&1.logical_source == :telemetry))
    assert Enum.any?(result.dashboard_warnings, &(&1.code == :watermark_unknown))

    placement_frames = result.frames_by_placement["placement_battery_voltage"]
    assert [_telemetry_frame] = placement_frames.primary
    assert %{limits: [_limits_frame]} = placement_frames.overlays

    assert_receive {:telemetry_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", _opts}

    assert_receive {:limits_latest, "org_dashboards", "mission_dashboards",
                    "tlm.hk.battery_voltage", _opts}
  end

  test "validates dashboard actions carried in frame, field, and warning metadata" do
    action = %DashboardAction{
      action_id: "action-telemetry-explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :navigate,
      route: "/missions/mission_dashboards/ops/telemetry/explore?point_id=HK.counter",
      query: %{"point_id" => "HK.counter"},
      context: %{placement_id: "placement-action"},
      presentation: :button,
      source: :widget
    }

    result = %Cadence.Dashboards.DashboardResolveResult{
      dashboard_id: "dashboard-actions",
      resolve_mode: :context_change,
      frames_by_placement: %{
        "placement-action" => %PlacementFrames{
          primary: [
            %Frame{
              source: :telemetry,
              shape: :scalar,
              fields: [
                %Field{
                  name: "value",
                  kind: :number,
                  values: [12.25],
                  metadata: %{actions: [%DashboardAction{action | source: :data_link_panel}]}
                }
              ],
              meta: %{actions: [action]}
            }
          ],
          warnings: [
            %ResolveWarning{
              code: :source_health_degraded,
              details: %{actions: [%DashboardAction{action | source: :warning}]}
            }
          ],
          planned_request_ids: ["source-request-action"]
        }
      },
      plan_metadata: valid_plan_metadata()
    }

    assert :ok = DashboardContract.validate_plan_result(result)
  end

  test "reports path-tagged violations for contract drift" do
    assert {:error, violations} =
             DashboardContract.validate_plan_result(%Cadence.Dashboards.DashboardResolveResult{
               dashboard_id: nil,
               resolve_mode: :bogus,
               frames_by_placement: %{
                 "placement-action" => %PlacementFrames{
                   primary: [
                     %Frame{
                       source: :telemetry,
                       shape: :scalar,
                       fields: [
                         %Field{
                           name: "value",
                           kind: :number,
                           values: [],
                           metadata: %{
                             actions: [
                               %DashboardAction{
                                 action_id: nil,
                                 label: "",
                                 target: :telemetry_sample,
                                 kind: :navigate,
                                 route: nil,
                                 query: "not-a-map",
                                 context: "not-a-map",
                                 presentation: :modal,
                                 source: :unknown
                               }
                             ]
                           }
                         }
                       ],
                       meta: %{actions: ["not-an-action"]}
                     }
                   ]
                 }
               },
               dashboard_warnings: [
                 %ResolveWarning{
                   code: nil,
                   severity: :critical,
                   details: "not-a-map",
                   links: [
                     %DataLink{
                       link_id: nil,
                       label: "",
                       target: :command,
                       target_id: nil,
                       context: "not-a-map",
                       presentation: :modal,
                       source: :unknown
                     }
                   ]
                 }
               ],
               plan_metadata: %{}
             })

    assert violation?(violations, [:dashboard_id], :invalid_binary)
    assert violation?(violations, [:resolve_mode], :unsupported_value)

    assert violation?(
             violations,
             [:frames_by_placement, "placement-action", :primary, 0, :meta, :actions, 0],
             :invalid_dashboard_action
           )

    assert violation?(
             violations,
             [
               :frames_by_placement,
               "placement-action",
               :primary,
               0,
               :fields,
               0,
               :metadata,
               :actions,
               0,
               :action_id
             ],
             :invalid_binary
           )

    assert violation?(
             violations,
             [
               :frames_by_placement,
               "placement-action",
               :primary,
               0,
               :fields,
               0,
               :metadata,
               :actions,
               0,
               :target
             ],
             :unsupported_value
           )

    assert violation?(
             violations,
             [
               :frames_by_placement,
               "placement-action",
               :primary,
               0,
               :fields,
               0,
               :metadata,
               :actions,
               0,
               :route
             ],
             :invalid_binary
           )

    assert violation?(
             violations,
             [
               :frames_by_placement,
               "placement-action",
               :primary,
               0,
               :fields,
               0,
               :metadata,
               :actions,
               0,
               :source
             ],
             :unsupported_value
           )

    assert violation?(violations, [:dashboard_warnings, 0, :code], :invalid_atom)
    assert violation?(violations, [:dashboard_warnings, 0, :severity], :unsupported_value)
    assert violation?(violations, [:dashboard_warnings, 0, :details], :invalid_map)
    assert violation?(violations, [:dashboard_warnings, 0, :links, 0, :link_id], :invalid_binary)
    assert violation?(violations, [:dashboard_warnings, 0, :links, 0, :label], :invalid_binary)

    assert violation?(
             violations,
             [:dashboard_warnings, 0, :links, 0, :target],
             :unsupported_value
           )

    assert violation?(
             violations,
             [:dashboard_warnings, 0, :links, 0, :target_id],
             :invalid_binary
           )

    assert violation?(violations, [:dashboard_warnings, 0, :links, 0, :context], :invalid_map)

    assert violation?(
             violations,
             [:dashboard_warnings, 0, :links, 0, :presentation],
             :unsupported_value
           )

    assert violation?(
             violations,
             [:dashboard_warnings, 0, :links, 0, :source],
             :unsupported_value
           )

    assert violation?(violations, [:plan_metadata, :cache], :missing_key)
  end

  test "engine contract validation raises before planning invalid requests" do
    document = load_fixture!("value_tile_latest.v1.json")

    invalid_request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: nil,
      document: document,
      resolve_mode: :bogus
    }

    assert_raise ArgumentError, ~r/dashboard request contract violated/, fn ->
      Engine.plan(invalid_request, validate_dashboard_contract?: true)
    end
  end

  defp resolve_request(document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
    }
  end

  defp valid_plan_metadata do
    %{
      cache: %{
        plan_key: %RuntimeCacheKey{layer: :plan, fingerprint: "contract-action-plan", parts: %{}},
        dependencies: %{},
        plan_cache: %{status: :disabled}
      },
      time: %{},
      snapshot?: false,
      live_append_eligible?: true,
      source_request_count: 0,
      unbatched_source_request_count: 0,
      batched_consumer_count: 0,
      degraded?: false
    }
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp telemetry_sample(mission_id, point_id) do
    %Sample{
      sample_id: "contract-sample-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: 12.25,
      engineering_value: 12.25,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp limit_event(mission_id, point_id) do
    %Event{
      limit_event_id: "contract-limit-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "contract-sample-1",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 12.25,
      limit_state: :green,
      normalized_state: :green,
      violation: false,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp best_effort_watermark(cursor) do
    {:ok,
     %{
       complete_through: cursor,
       latest_receipt_time: cursor,
       retention_starts_at: ~U[2026-06-17 11:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  defp violation?(violations, path, code) do
    Enum.any?(violations, &match?(%{path: ^path, code: ^code}, &1))
  end
end
