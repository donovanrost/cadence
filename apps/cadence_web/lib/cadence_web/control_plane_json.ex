defmodule CadenceWeb.ControlPlaneJSON do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.{DispatchDecision, WorkItem}
  alias Cadence.Auth.Scope
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Catalog.{Artifact, ImporterDescriptor, ImportRun}
  alias Cadence.Catalog.Command.Compiler.Result, as: CommandCompilerResult
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: TelemetryCompilerResult
  alias Cadence.Catalog.Telemetry.Compiler.SelectorInput
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandStage,
    CommandVerifierInstance,
    StagedCommandItem
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.MissionEvents.Entry, as: MissionEventEntry
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Protocol.{PacketRecord, ProtocolAnomaly, TransferFrameRecord}

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance,
    Selector,
    SelectorMatch,
    SelectorScope
  }

  alias Cadence.Contacts.{
    ContactAction,
    LinkAssignment,
    Path,
    PathTemplate,
    ProviderBinding,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    TransportBinding,
    TransportProfile
  }

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Reads.MissionHealth
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition, Sample}

  @spec bootstrap(map()) :: map()
  def bootstrap(%{
        organization: %Organization{} = organization,
        mission: mission,
        service_identity: %ServiceIdentity{} = service_identity,
        api_token: api_token
      }) do
    %{
      organization: organization(organization),
      mission: if(mission, do: mission(mission), else: nil),
      service_identity:
        issued_service_identity(%{
          service_identity: service_identity,
          api_token: api_token
        })
    }
  end

  @spec bootstrap_admin_session(map()) :: map()
  def bootstrap_admin_session(%{
        user: %User{} = user,
        session_token: session_token,
        expires_at: %DateTime{} = expires_at
      }) do
    %{
      user: user(user),
      session_token: session_token,
      expires_at: iso8601(expires_at)
    }
  end

  @spec current_scope(Scope.t()) :: map()
  def current_scope(%Scope{} = current_scope) do
    %{
      actor_kind: Atom.to_string(current_scope.actor_kind),
      organization:
        if(current_scope.organization, do: organization(current_scope.organization), else: nil),
      mission: if(current_scope.mission, do: mission(current_scope.mission), else: nil),
      user: if(current_scope.user, do: user(current_scope.user), else: nil),
      service_identity:
        if(current_scope.service_identity,
          do: service_identity(current_scope.service_identity),
          else: nil
        ),
      capabilities: current_scope.capabilities |> MapSet.to_list() |> Enum.map(&Atom.to_string/1)
    }
  end

  @spec user(User.t()) :: map()
  def user(%User{} = user) do
    %{
      user_id: user.user_id,
      email: user.email,
      display_name: user.display_name,
      capabilities: Enum.map(user.capabilities, &Atom.to_string/1),
      lifecycle_state: Atom.to_string(user.lifecycle_state),
      metadata: user.metadata
    }
  end

  @spec organization(Organization.t()) :: map()
  def organization(%Organization{} = organization) do
    %{
      organization_id: organization.organization_id,
      slug: organization.slug,
      display_name: organization.display_name,
      metadata: organization.metadata
    }
  end

  @spec mission(Mission.t()) :: map()
  def mission(%Mission{} = mission) do
    %{
      mission_id: mission.mission_id,
      organization_id: mission.organization_id,
      slug: mission.slug,
      display_name: mission.display_name,
      metadata: mission.metadata
    }
  end

  @spec service_identity(ServiceIdentity.t()) :: map()
  def service_identity(%ServiceIdentity{} = service_identity) do
    %{
      service_identity_id: service_identity.service_identity_id,
      organization_id: service_identity.organization_id,
      mission_id: service_identity.mission_id,
      display_name: service_identity.display_name,
      capabilities: Enum.map(service_identity.capabilities, &Atom.to_string/1),
      lifecycle_state: Atom.to_string(service_identity.lifecycle_state),
      token_hint: service_identity.token_hint,
      metadata: service_identity.metadata
    }
  end

  @spec issued_service_identity(map()) :: map()
  def issued_service_identity(%{
        service_identity: %ServiceIdentity{} = service_identity,
        api_token: api_token
      }) do
    %{
      service_identity: service_identity(service_identity),
      api_token: api_token
    }
  end

  @spec source_endpoint(SourceEndpoint.t()) :: map()
  def source_endpoint(%SourceEndpoint{} = source_endpoint) do
    %{
      source_endpoint_id: source_endpoint.source_endpoint_id,
      organization_id: source_endpoint.organization_id,
      mission_id: source_endpoint.mission_id,
      spacecraft_id: source_endpoint.spacecraft_id,
      source_ref: source_endpoint.source_ref,
      scid: source_endpoint.scid,
      display_name: source_endpoint.display_name,
      metadata: source_endpoint.metadata
    }
  end

  @spec spacecraft(Spacecraft.t()) :: map()
  def spacecraft(%Spacecraft{} = spacecraft) do
    %{
      spacecraft_id: spacecraft.spacecraft_id,
      organization_id: spacecraft.organization_id,
      mission_id: spacecraft.mission_id,
      display_name: spacecraft.display_name,
      scid: spacecraft.scid,
      metadata: spacecraft.metadata
    }
  end

  @spec packet_definition(PacketDefinition.t()) :: map()
  def packet_definition(%PacketDefinition{} = packet_definition) do
    %{
      packet_definition_id: packet_definition.packet_definition_id,
      organization_id: packet_definition.organization_id,
      mission_id: packet_definition.mission_id,
      packet_name: packet_definition.packet_name,
      apid: packet_definition.apid,
      version: packet_definition.version,
      fields: Enum.map(packet_definition.fields, &field_definition/1)
    }
  end

  @spec catalog_importer(%{module: module(), descriptor: ImporterDescriptor.t()}) :: map()
  def catalog_importer(%{module: module, descriptor: %ImporterDescriptor{} = descriptor}) do
    %{
      module: inspect(module),
      importer_key: descriptor.importer_key,
      display_name: descriptor.display_name,
      catalog_family: Atom.to_string(descriptor.catalog_family),
      source_formats: descriptor.source_formats,
      media_types: descriptor.media_types,
      description: descriptor.description
    }
  end

  @spec catalog_artifact(Artifact.t()) :: map()
  def catalog_artifact(%Artifact{} = artifact) do
    %{
      artifact_id: artifact.artifact_id,
      organization_id: artifact.organization_id,
      mission_id: artifact.mission_id,
      catalog_database_id: artifact.catalog_database_id,
      catalog_family: Atom.to_string(artifact.catalog_family),
      artifact_name: artifact.artifact_name,
      format_key: artifact.format_key,
      format_version: artifact.format_version,
      media_type: artifact.media_type,
      source_artifact: artifact.source_artifact,
      content_sha256: artifact.content_sha256,
      uploaded_by: artifact.uploaded_by,
      uploaded_at: iso8601(artifact.uploaded_at),
      metadata: artifact.metadata
    }
  end

  @spec catalog_import_run(ImportRun.t()) :: map()
  def catalog_import_run(%ImportRun{} = import_run) do
    %{
      import_run_id: import_run.import_run_id,
      snapshot_id: import_run.snapshot_id,
      organization_id: import_run.organization_id,
      mission_id: import_run.mission_id,
      catalog_database_id: import_run.catalog_database_id,
      artifact_id: import_run.artifact_id,
      catalog_family: Atom.to_string(import_run.catalog_family),
      importer_key: import_run.importer_key,
      status: Atom.to_string(import_run.status),
      imported_definition_count: import_run.imported_definition_count,
      diagnostics: Enum.map(import_run.diagnostics, &catalog_diagnostic/1),
      result_document: import_run.result_document,
      failure_reason: import_run.failure_reason,
      requested_by: import_run.requested_by,
      started_at: iso8601(import_run.started_at),
      completed_at: iso8601(import_run.completed_at),
      metadata: import_run.metadata
    }
  end

  @spec catalog_telemetry_snapshot_summary(TelemetryCatalogSnapshot.t()) :: map()
  def catalog_telemetry_snapshot_summary(%TelemetryCatalogSnapshot{} = snapshot) do
    %{
      snapshot_id: snapshot.snapshot_id,
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      artifact_id: snapshot.artifact_id,
      import_run_id: snapshot.import_run_id,
      importer_key: snapshot.importer_key,
      snapshot_name: snapshot.snapshot_name,
      snapshot_version: snapshot.snapshot_version,
      description: snapshot.description,
      published_at: iso8601(snapshot.published_at),
      superseded_at: iso8601(snapshot.superseded_at),
      packet_count: length(snapshot.packets),
      point_count: length(snapshot.points),
      type_count: length(snapshot.types),
      unit_count: length(snapshot.units),
      calibration_algorithm_count: length(snapshot.calibration_algorithms)
    }
  end

  @spec catalog_telemetry_snapshot(TelemetryCatalogSnapshot.t()) :: map()
  def catalog_telemetry_snapshot(%TelemetryCatalogSnapshot{} = snapshot) do
    catalog_telemetry_snapshot_summary(snapshot)
    |> Map.put(:snapshot_document, JsonDocument.encode(snapshot))
  end

  @spec catalog_command_snapshot_summary(CommandCatalogSnapshot.t()) :: map()
  def catalog_command_snapshot_summary(%CommandCatalogSnapshot{} = snapshot) do
    %{
      snapshot_id: snapshot.snapshot_id,
      organization_id: snapshot.organization_id,
      mission_id: snapshot.mission_id,
      artifact_id: snapshot.artifact_id,
      import_run_id: snapshot.import_run_id,
      importer_key: snapshot.importer_key,
      snapshot_name: snapshot.snapshot_name,
      snapshot_version: snapshot.snapshot_version,
      description: snapshot.description,
      published_at: iso8601(snapshot.published_at),
      superseded_at: iso8601(snapshot.superseded_at),
      command_count: length(snapshot.command_definitions),
      argument_count: length(snapshot.arguments),
      argument_type_count: length(snapshot.argument_types),
      encoding_layout_count: length(snapshot.encoding_layouts)
    }
  end

  @spec catalog_command_snapshot(CommandCatalogSnapshot.t()) :: map()
  def catalog_command_snapshot(%CommandCatalogSnapshot{} = snapshot) do
    catalog_command_snapshot_summary(snapshot)
    |> Map.put(:snapshot_document, JsonDocument.encode(snapshot))
  end

  @spec catalog_telemetry_recompile_result(map()) :: map()
  def catalog_telemetry_recompile_result(%{
        snapshot: %TelemetryCatalogSnapshot{} = snapshot,
        compiler_result: %TelemetryCompilerResult{} = compiler_result,
        binding_set: %BindingSet{} = binding_set
      }) do
    %{
      snapshot: catalog_telemetry_snapshot_summary(snapshot),
      compiler_result: %{
        packet_definition_count: length(compiler_result.packet_definitions),
        selector_input_count: length(compiler_result.selector_inputs),
        diagnostic_count: length(compiler_result.diagnostics),
        diagnostics: Enum.map(compiler_result.diagnostics, &catalog_diagnostic/1),
        packet_definitions:
          Enum.map(compiler_result.packet_definitions, fn packet_definition ->
            %{
              packet_definition_id: packet_definition.packet_definition_id,
              packet_name: packet_definition.packet_name,
              apid: packet_definition.apid,
              version: packet_definition.version,
              field_count: length(packet_definition.fields)
            }
          end),
        selector_inputs: Enum.map(compiler_result.selector_inputs, &catalog_selector_input/1)
      },
      binding_set: %{
        binding_set_id: binding_set.binding_set_id,
        version: binding_set.version,
        capability_instance_count: length(binding_set.capability_instances),
        rule_count: length(binding_set.rules)
      }
    }
  end

  @spec catalog_telemetry_runtime_diff(map()) :: map()
  def catalog_telemetry_runtime_diff(report) when is_map(report) do
    %{
      snapshot_id: report.snapshot_id,
      import_run_id: report.import_run_id,
      compiler_summary: report.compiler_summary,
      compiler_diagnostics: Enum.map(report.compiler_diagnostics, &catalog_diagnostic/1),
      expected_binding_set: report.expected_binding_set,
      existing_binding_set: report.existing_binding_set,
      packet_definitions: report.packet_definitions,
      capability_instances: report.capability_instances,
      binding_rules: report.binding_rules
    }
  end

  @spec catalog_telemetry_materialization_result(map()) :: map()
  def catalog_telemetry_materialization_result(result) when is_map(result) do
    catalog_telemetry_recompile_result(result)
  end

  @spec catalog_command_compile_result(CommandCatalogSnapshot.t(), CommandCompilerResult.t()) ::
          map()
  def catalog_command_compile_result(
        %CommandCatalogSnapshot{} = snapshot,
        %CommandCompilerResult{} = compiler_result
      ) do
    %{
      snapshot: catalog_command_snapshot_summary(snapshot),
      compiler_result: %{
        runtime_definition_count: length(compiler_result.runtime_definitions),
        constraint_plan_count: length(compiler_result.constraint_plans),
        verifier_plan_count: length(compiler_result.verifier_plans),
        operational_binding_count: length(compiler_result.operational_bindings),
        diagnostic_count: length(compiler_result.diagnostics),
        diagnostics: Enum.map(compiler_result.diagnostics, &catalog_diagnostic/1),
        runtime_definitions:
          Enum.map(compiler_result.runtime_definitions, fn runtime_definition ->
            %{
              command_id: runtime_definition.command_id,
              name: runtime_definition.name,
              apid: runtime_definition.apid,
              opcode: runtime_definition.opcode,
              argument_count: length(runtime_definition.argument_specs)
            }
          end)
      }
    }
  end

  @spec telemetry_sample(Sample.t()) :: map()
  def telemetry_sample(%Sample{} = sample) do
    %{
      sample_id: sample.sample_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id,
      point_name: sample.point_name,
      packet_definition_id: sample.packet_definition_id,
      packet_definition_version: sample.packet_definition_version,
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      raw_value: JsonDocument.encode(sample.raw_value),
      engineering_value: JsonDocument.encode(sample.engineering_value),
      quality_state: Atom.to_string(sample.quality_state),
      generation_time: iso8601(sample.generation_time),
      receipt_time: iso8601(sample.receipt_time),
      provenance: JsonDocument.encode(sample.provenance)
    }
  end

  @spec dev_ingress_result(map()) :: map()
  def dev_ingress_result(%{
        raw_evidence: %RawEvidence{} = raw_evidence,
        packet_records: packet_records,
        transfer_frame_records: transfer_frame_records,
        protocol_anomalies: protocol_anomalies,
        dispatch_decisions: dispatch_decisions,
        outputs: outputs
      }) do
    %{
      raw_evidence: raw_evidence(raw_evidence),
      packet_records: Enum.map(packet_records, &packet_record/1),
      transfer_frame_records: Enum.map(transfer_frame_records, &transfer_frame_record/1),
      protocol_anomalies: Enum.map(protocol_anomalies, &protocol_anomaly/1),
      dispatch_decisions: Enum.map(dispatch_decisions, &dispatch_decision/1),
      outputs: Enum.map(outputs, &runtime_output/1)
    }
  end

  @spec binding_set(BindingSet.t()) :: map()
  def binding_set(%BindingSet{} = binding_set) do
    %{
      binding_set_id: binding_set.binding_set_id,
      organization_id: binding_set.organization_id,
      mission_id: binding_set.mission_id,
      version: binding_set.version,
      capability_instances: Enum.map(binding_set.capability_instances, &capability_instance/1),
      rules: Enum.map(binding_set.rules, &binding_rule/1)
    }
  end

  @spec command_stage(CommandStage.t()) :: map()
  def command_stage(%CommandStage{} = command_stage) do
    %{
      command_stage_id: command_stage.command_stage_id,
      organization_id: command_stage.organization_id,
      mission_id: command_stage.mission_id,
      stage_name: command_stage.stage_name,
      description: command_stage.description,
      owner: command_stage.owner,
      visibility: Atom.to_string(command_stage.visibility),
      lifecycle_state: Atom.to_string(command_stage.lifecycle_state),
      metadata: command_stage.metadata
    }
  end

  @spec staged_command_item(StagedCommandItem.t()) :: map()
  def staged_command_item(%StagedCommandItem{} = staged_command_item) do
    %{
      staged_command_item_id: staged_command_item.staged_command_item_id,
      organization_id: staged_command_item.organization_id,
      mission_id: staged_command_item.mission_id,
      command_stage_id: staged_command_item.command_stage_id,
      source_endpoint_ref: staged_command_item.source_endpoint_ref,
      command_snapshot_id: staged_command_item.command_snapshot_id,
      command_id: staged_command_item.command_id,
      argument_values: JsonDocument.encode(staged_command_item.argument_values),
      priority: staged_command_item.priority,
      not_before: iso8601(staged_command_item.not_before),
      expires_at: iso8601(staged_command_item.expires_at),
      notes: staged_command_item.notes,
      item_order: staged_command_item.item_order,
      lifecycle_state: Atom.to_string(staged_command_item.lifecycle_state),
      submitted_command_request_id: staged_command_item.submitted_command_request_id,
      metadata: JsonDocument.encode(staged_command_item.metadata)
    }
  end

  @spec command_request(CommandRequest.t()) :: map()
  def command_request(%CommandRequest{} = command_request) do
    %{
      command_request_id: command_request.command_request_id,
      organization_id: command_request.organization_id,
      mission_id: command_request.mission_id,
      source_endpoint_ref: command_request.source_endpoint_ref,
      command_snapshot_id: command_request.command_snapshot_id,
      command_id: command_request.command_id,
      command_name: command_request.command_name,
      command_display_name: command_request.command_display_name,
      lifecycle_state: Atom.to_string(command_request.lifecycle_state),
      verification_state: maybe_atom_to_string(command_request.verification_state),
      priority: command_request.priority,
      not_before: iso8601(command_request.not_before),
      expires_at: iso8601(command_request.expires_at),
      requested_by: JsonDocument.encode(command_request.requested_by),
      source_command_stage_id: command_request.source_command_stage_id,
      source_staged_command_item_id: command_request.source_staged_command_item_id,
      argument_values: JsonDocument.encode(command_request.argument_values),
      resolved_argument_values: JsonDocument.encode(command_request.resolved_argument_values),
      significance: maybe_atom_to_string(command_request.significance),
      critical: command_request.critical,
      hazardous: command_request.hazardous,
      subsystem: command_request.subsystem,
      group_name: command_request.group_name,
      preferred_uplink_service: command_request.preferred_uplink_service,
      release_policy_hint: command_request.release_policy_hint,
      apid: command_request.apid,
      service_type: command_request.service_type,
      service_subtype: command_request.service_subtype,
      opcode: JsonDocument.encode(command_request.opcode),
      requested_at: iso8601(command_request.requested_at),
      metadata: JsonDocument.encode(command_request.metadata)
    }
  end

  @spec command_approval(CommandApproval.t()) :: map()
  def command_approval(%CommandApproval{} = command_approval) do
    %{
      command_approval_id: command_approval.command_approval_id,
      organization_id: command_approval.organization_id,
      mission_id: command_approval.mission_id,
      command_request_id: command_approval.command_request_id,
      decision: Atom.to_string(command_approval.decision),
      decided_by: JsonDocument.encode(command_approval.decided_by),
      decided_at: iso8601(command_approval.decided_at),
      reason: command_approval.reason,
      metadata: JsonDocument.encode(command_approval.metadata)
    }
  end

  @spec command_queue_entry(CommandQueueEntry.t()) :: map()
  def command_queue_entry(%CommandQueueEntry{} = command_queue_entry) do
    %{
      command_queue_entry_id: command_queue_entry.command_queue_entry_id,
      organization_id: command_queue_entry.organization_id,
      mission_id: command_queue_entry.mission_id,
      command_request_id: command_queue_entry.command_request_id,
      source_endpoint_ref: command_queue_entry.source_endpoint_ref,
      queue_lane_key: command_queue_entry.queue_lane_key,
      priority: command_queue_entry.priority,
      queue_sequence: command_queue_entry.queue_sequence,
      not_before: iso8601(command_queue_entry.not_before),
      expires_at: iso8601(command_queue_entry.expires_at),
      lifecycle_state: Atom.to_string(command_queue_entry.lifecycle_state),
      enqueued_by: JsonDocument.encode(command_queue_entry.enqueued_by),
      enqueued_at: iso8601(command_queue_entry.enqueued_at),
      metadata: JsonDocument.encode(command_queue_entry.metadata)
    }
  end

  @spec command_release_attempt(CommandReleaseAttempt.t()) :: map()
  def command_release_attempt(%CommandReleaseAttempt{} = command_release_attempt) do
    %{
      command_release_attempt_id: command_release_attempt.command_release_attempt_id,
      organization_id: command_release_attempt.organization_id,
      mission_id: command_release_attempt.mission_id,
      command_queue_entry_id: command_release_attempt.command_queue_entry_id,
      command_request_id: command_release_attempt.command_request_id,
      source_endpoint_ref: command_release_attempt.source_endpoint_ref,
      realized_contact_id: command_release_attempt.realized_contact_id,
      path_id: command_release_attempt.path_id,
      transport_binding_id: command_release_attempt.transport_binding_id,
      command_snapshot_id: command_release_attempt.command_snapshot_id,
      command_id: command_release_attempt.command_id,
      command_name: command_release_attempt.command_name,
      layout_kind: maybe_atom_to_string(command_release_attempt.layout_kind),
      preferred_uplink_service: command_release_attempt.preferred_uplink_service,
      apid: command_release_attempt.apid,
      service_type: command_release_attempt.service_type,
      service_subtype: command_release_attempt.service_subtype,
      opcode: JsonDocument.encode(command_release_attempt.opcode),
      encoded_binary_base64: command_release_attempt.encoded_binary_base64,
      encoded_size_bytes: command_release_attempt.encoded_size_bytes,
      lifecycle_state: Atom.to_string(command_release_attempt.lifecycle_state),
      verification_state: maybe_atom_to_string(command_release_attempt.verification_state),
      failure_reason: command_release_attempt.failure_reason,
      released_by: JsonDocument.encode(command_release_attempt.released_by),
      attempted_at: iso8601(command_release_attempt.attempted_at),
      released_at: iso8601(command_release_attempt.released_at),
      metadata: JsonDocument.encode(command_release_attempt.metadata)
    }
  end

  @spec command_verifier_instance(CommandVerifierInstance.t()) :: map()
  def command_verifier_instance(%CommandVerifierInstance{} = command_verifier_instance) do
    %{
      command_verifier_instance_id: command_verifier_instance.command_verifier_instance_id,
      organization_id: command_verifier_instance.organization_id,
      mission_id: command_verifier_instance.mission_id,
      command_request_id: command_verifier_instance.command_request_id,
      command_release_attempt_id: command_verifier_instance.command_release_attempt_id,
      source_endpoint_ref: command_verifier_instance.source_endpoint_ref,
      command_snapshot_id: command_verifier_instance.command_snapshot_id,
      command_id: command_verifier_instance.command_id,
      command_name: command_verifier_instance.command_name,
      verifier_id: command_verifier_instance.verifier_id,
      verifier_name: command_verifier_instance.verifier_name,
      phase: Atom.to_string(command_verifier_instance.phase),
      severity: maybe_atom_to_string(command_verifier_instance.severity),
      success_criteria: JsonDocument.encode(command_verifier_instance.success_criteria),
      failure_criteria: JsonDocument.encode(command_verifier_instance.failure_criteria),
      delay_until: iso8601(command_verifier_instance.delay_until),
      timeout_at: iso8601(command_verifier_instance.timeout_at),
      lifecycle_state: Atom.to_string(command_verifier_instance.lifecycle_state),
      matched_record_kind: maybe_atom_to_string(command_verifier_instance.matched_record_kind),
      matched_record_id: command_verifier_instance.matched_record_id,
      matched_at: iso8601(command_verifier_instance.matched_at),
      failure_reason: command_verifier_instance.failure_reason,
      metadata: JsonDocument.encode(command_verifier_instance.metadata)
    }
  end

  @spec command_request_decision_result(map()) :: map()
  def command_request_decision_result(%{
        approval: %CommandApproval{} = approval,
        command_request: %CommandRequest{} = command_request
      }) do
    %{
      approval: command_approval(approval),
      command_request: command_request(command_request)
    }
  end

  @spec command_request_enqueue_result(map()) :: map()
  def command_request_enqueue_result(%{
        queue_entry: %CommandQueueEntry{} = queue_entry,
        command_request: %CommandRequest{} = command_request
      }) do
    %{
      queue_entry: command_queue_entry(queue_entry),
      command_request: command_request(command_request)
    }
  end

  @spec command_queue_entry_release_result(map()) :: map()
  def command_queue_entry_release_result(%{
        release_attempt: %CommandReleaseAttempt{} = release_attempt,
        queue_entry: %CommandQueueEntry{} = queue_entry,
        command_request: %CommandRequest{} = command_request
      }) do
    %{
      release_attempt: command_release_attempt(release_attempt),
      queue_entry: command_queue_entry(queue_entry),
      command_request: command_request(command_request)
    }
  end

  @spec activation(BindingSetActivation.t()) :: map()
  def activation(%BindingSetActivation{} = activation) do
    %{
      activation_id: activation.activation_id,
      organization_id: activation.organization_id,
      mission_id: activation.mission_id,
      binding_set_id: activation.binding_set_id,
      binding_set_version: activation.binding_set_version,
      activated_at: iso8601(activation.activated_at),
      metadata: activation.metadata
    }
  end

  @spec active_binding_set(BindingSetActivation.t(), BindingSet.t()) :: map()
  def active_binding_set(%BindingSetActivation{} = activation, %BindingSet{} = binding_set) do
    %{
      activation: activation(activation),
      binding_set: binding_set(binding_set)
    }
  end

  @spec scheduled_contact(ScheduledContact.t()) :: map()
  def scheduled_contact(%ScheduledContact{} = scheduled_contact) do
    %{
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      organization_id: scheduled_contact.organization_id,
      mission_id: scheduled_contact.mission_id,
      source_endpoint_refs: scheduled_contact.source_endpoint_refs,
      contact_intents: Enum.map(scheduled_contact.contact_intents, &Atom.to_string/1),
      link_assignment_refs: json_value(scheduled_contact.link_assignment_refs),
      path_template_ids: scheduled_contact.path_template_ids,
      path_template_refs: json_value(scheduled_contact.path_template_refs),
      paths: Enum.map(scheduled_contact.paths, &contact_path/1),
      starts_at: iso8601(scheduled_contact.starts_at),
      ends_at: iso8601(scheduled_contact.ends_at),
      provider_contact_ref: scheduled_contact.provider_contact_ref,
      current_revision: scheduled_contact.current_revision,
      lifecycle_state: Atom.to_string(scheduled_contact.lifecycle_state),
      realized_contact_id: scheduled_contact.realized_contact_id,
      metadata: scheduled_contact.metadata
    }
  end

  @spec provider_profile(ProviderProfile.t()) :: map()
  def provider_profile(%ProviderProfile{} = provider_profile) do
    %{
      provider_profile_id: provider_profile.provider_profile_id,
      organization_id: provider_profile.organization_id,
      mission_id: provider_profile.mission_id,
      version: provider_profile.version,
      lifecycle_state: maybe_atom_to_string(provider_profile.lifecycle_state),
      adapter_key: maybe_atom_to_string(provider_profile.adapter_key),
      configuration: json_value(provider_profile.configuration),
      metadata: json_value(provider_profile.metadata)
    }
  end

  @spec transport_profile(TransportProfile.t()) :: map()
  def transport_profile(%TransportProfile{} = transport_profile) do
    %{
      transport_profile_id: transport_profile.transport_profile_id,
      organization_id: transport_profile.organization_id,
      mission_id: transport_profile.mission_id,
      version: transport_profile.version,
      lifecycle_state: maybe_atom_to_string(transport_profile.lifecycle_state),
      family_key: maybe_atom_to_string(transport_profile.family_key),
      target_scope: maybe_atom_to_string(transport_profile.target_scope),
      configuration: json_value(transport_profile.configuration),
      metadata: json_value(transport_profile.metadata)
    }
  end

  @spec path_template(PathTemplate.t()) :: map()
  def path_template(%PathTemplate{} = path_template) do
    %{
      path_template_id: path_template.path_template_id,
      organization_id: path_template.organization_id,
      mission_id: path_template.mission_id,
      version: path_template.version,
      lifecycle_state: maybe_atom_to_string(path_template.lifecycle_state),
      path_id: path_template.path_id,
      direction: maybe_atom_to_string(path_template.direction),
      selection_role: maybe_atom_to_string(path_template.selection_role),
      source_endpoint_ref: path_template.source_endpoint_ref,
      provider_path_ref: path_template.provider_path_ref,
      provider_profile_ids: path_template.provider_profile_ids,
      provider_profile_refs: json_value(path_template.provider_profile_refs),
      transport_profile_ids: path_template.transport_profile_ids,
      transport_profile_refs: json_value(path_template.transport_profile_refs),
      metadata: json_value(path_template.metadata)
    }
  end

  @spec link_assignment(LinkAssignment.t()) :: map()
  def link_assignment(%LinkAssignment{} = link_assignment) do
    %{
      link_assignment_id: link_assignment.link_assignment_id,
      organization_id: link_assignment.organization_id,
      mission_id: link_assignment.mission_id,
      lifecycle_state: maybe_atom_to_string(link_assignment.lifecycle_state),
      spacecraft_id: link_assignment.spacecraft_id,
      source_endpoint_ref: link_assignment.source_endpoint_ref,
      path_template_id: link_assignment.path_template_id,
      path_template_version: link_assignment.path_template_version,
      direction: maybe_atom_to_string(link_assignment.direction),
      selection_role: maybe_atom_to_string(link_assignment.selection_role),
      provider_path_ref: link_assignment.provider_path_ref,
      provider_profile_refs: json_value(link_assignment.provider_profile_refs),
      transport_profile_refs: json_value(link_assignment.transport_profile_refs),
      metadata: json_value(link_assignment.metadata)
    }
  end

  @spec link_template_application_result(map()) :: map()
  def link_template_application_result(result) when is_map(result) do
    %{
      applied_count: result.applied_count,
      skipped_count: result.skipped_count,
      failed_count: result.failed_count,
      rows: Enum.map(result.rows, &link_template_application_row/1)
    }
  end

  defp link_template_application_row(row) when is_map(row) do
    %{
      id: row.id,
      spacecraft: spacecraft(row.spacecraft),
      kind: maybe_atom_to_string(row.kind),
      status: maybe_atom_to_string(row.status),
      label: row.label,
      detail: row.detail
    }
  end

  @spec realized_contact(RealizedContact.t()) :: map()
  def realized_contact(%RealizedContact{} = realized_contact) do
    %{
      realized_contact_id: realized_contact.realized_contact_id,
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      source_endpoint_refs: realized_contact.source_endpoint_refs,
      contact_intents: Enum.map(realized_contact.contact_intents, &Atom.to_string/1),
      paths: Enum.map(realized_contact.paths, &contact_path/1),
      clock_mode: Atom.to_string(realized_contact.clock_mode),
      initial_time: iso8601(realized_contact.initial_time),
      lifecycle_state: Atom.to_string(realized_contact.lifecycle_state),
      realized_at: iso8601(realized_contact.realized_at),
      metadata: realized_contact.metadata
    }
  end

  @spec realized_contact_runtime_snapshot(map()) :: map()
  def realized_contact_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      realized_contact_id: snapshot_value(snapshot, :realized_contact_id),
      mission_id: snapshot_value(snapshot, :mission_id),
      source_endpoint_refs: snapshot_value(snapshot, :source_endpoint_refs, []),
      contact_intents: snapshot_value(snapshot, :contact_intents, []),
      clock_mode: snapshot_atom_string(snapshot, :clock_mode),
      initial_time: snapshot_iso8601(snapshot, :initial_time),
      metadata: snapshot_json(snapshot, :metadata, %{}),
      path_count: snapshot_value(snapshot, :path_count, 0),
      paths: snapshot_list(snapshot, :paths, &path_runtime_snapshot/1),
      downlink_combiner: snapshot_json(snapshot, :downlink_combiner, %{})
    }
  end

  @spec path_runtime_snapshot(map()) :: map()
  def path_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      realized_contact_id: snapshot_value(snapshot, :realized_contact_id),
      mission_id: snapshot_value(snapshot, :mission_id),
      path_id: snapshot_value(snapshot, :path_id),
      direction: snapshot_atom_string(snapshot, :direction),
      selection_role: snapshot_atom_string(snapshot, :selection_role),
      source_endpoint_ref: snapshot_value(snapshot, :source_endpoint_ref),
      provider_path_ref: snapshot_value(snapshot, :provider_path_ref),
      metadata: snapshot_json(snapshot, :metadata, %{}),
      provider_runtime_count: snapshot_value(snapshot, :provider_runtime_count, 0),
      provider_runtimes:
        snapshot_list(snapshot, :provider_runtimes, &provider_runtime_snapshot/1),
      transport_runtime_count: snapshot_value(snapshot, :transport_runtime_count, 0),
      transport_runtimes:
        snapshot_list(snapshot, :transport_runtimes, &transport_runtime_snapshot/1)
    }
  end

  @spec contact_action(ContactAction.t()) :: map()
  def contact_action(%ContactAction{} = contact_action) do
    %{
      contact_action_id: contact_action.contact_action_id,
      organization_id: contact_action.organization_id,
      mission_id: contact_action.mission_id,
      scheduled_contact_id: contact_action.scheduled_contact_id,
      realized_contact_id: contact_action.realized_contact_id,
      action_kind: Atom.to_string(contact_action.action_kind),
      reason: contact_action.reason,
      actor: contact_action.actor,
      metadata: contact_action.metadata,
      occurred_at: iso8601(contact_action.occurred_at)
    }
  end

  @spec mission_event(binary(), MissionEventEntry.t()) :: map()
  def mission_event(organization_id, %MissionEventEntry{} = mission_event) do
    %{
      mission_event_id: mission_event.mission_event_id,
      organization_id: organization_id,
      mission_id: mission_event.mission_id,
      occurred_at: iso8601(mission_event.occurred_at),
      category: maybe_atom_to_string(mission_event.category),
      kind: maybe_atom_to_string(mission_event.kind),
      severity: maybe_atom_to_string(mission_event.severity),
      status: mission_event.status,
      title: mission_event.title,
      summary: mission_event.summary,
      source_record_kind: maybe_atom_to_string(mission_event.source_record_kind),
      source_record_id: mission_event.source_record_id,
      subject_kind: maybe_atom_to_string(mission_event.subject_kind),
      subject_id: mission_event.subject_id,
      correlation_key: mission_event.correlation_key,
      spacecraft_id: mission_event.spacecraft_id,
      source_endpoint_ref: mission_event.source_endpoint_ref,
      scheduled_contact_id: mission_event.scheduled_contact_id,
      realized_contact_id: mission_event.realized_contact_id,
      path_id: mission_event.path_id,
      capability_instance_id: mission_event.capability_instance_id,
      activation_id: mission_event.activation_id,
      actor: mission_event.actor,
      metadata: mission_event.metadata
    }
  end

  defp catalog_diagnostic(diagnostic) do
    %{
      severity: maybe_atom_to_string(diagnostic.severity),
      code: diagnostic.code,
      message: diagnostic.message,
      path: diagnostic.path,
      metadata: diagnostic.metadata
    }
  end

  @spec mission_health(binary(), MissionHealth.t()) :: map()
  def mission_health(organization_id, %MissionHealth{} = mission_health) do
    %{
      organization_id: organization_id,
      mission_id: mission_health.mission_id,
      total_points: mission_health.total_points,
      violating_points: mission_health.violating_points,
      normalized_state_counts: mission_health.normalized_state_counts,
      worst_normalized_state: maybe_atom_to_string(mission_health.worst_normalized_state),
      updated_at: iso8601(mission_health.updated_at),
      point_buckets: point_buckets(mission_health.point_buckets),
      scope_summaries: Enum.map(mission_health.scope_summaries, &scope_summary/1)
    }
  end

  defp capability_instance(%CapabilityInstance{} = capability_instance) do
    %{
      capability_instance_id: capability_instance.capability_instance_id,
      family_key: maybe_atom_to_string(capability_instance.family_key),
      target_scope: Atom.to_string(capability_instance.target_scope),
      source_endpoint_ref: capability_instance.source_endpoint_ref,
      lifecycle_state: Atom.to_string(capability_instance.lifecycle_state),
      capability_config: capability_config(capability_instance.capability_config)
    }
  end

  defp binding_rule(%BindingRule{} = binding_rule) do
    %{
      binding_rule_id: binding_rule.binding_rule_id,
      capability_instance_id: binding_rule.capability_instance_id,
      handler_key: maybe_atom_to_string(binding_rule.handler_key),
      selector: selector(binding_rule.selector),
      capability_config: capability_config(binding_rule.capability_config),
      priority: binding_rule.priority,
      fanout_mode: Atom.to_string(binding_rule.fanout_mode)
    }
  end

  defp selector(%Selector{} = selector) do
    %{
      scope: selector_scope(selector.scope),
      match: selector_match(selector.match)
    }
  end

  defp selector_scope(%SelectorScope{} = selector_scope) do
    %{
      target_scope: Atom.to_string(selector_scope.target_scope),
      source_endpoint_ref: selector_scope.source_endpoint_ref
    }
  end

  defp selector_match(%SelectorMatch{} = selector_match) do
    %{
      packet_kind: maybe_atom_to_string(selector_match.packet_kind),
      apid: selector_match.apid
    }
  end

  defp capability_config(nil), do: nil

  defp capability_config(%CapabilityConfig{} = capability_config) do
    %{
      config_type: Atom.to_string(capability_config.config_type),
      document: capability_config.document
    }
  end

  defp field_definition(%FieldDefinition{} = field_definition) do
    %{
      field_id: field_definition.field_id,
      name: field_definition.name,
      offset_bits: field_definition.offset_bits,
      size_bits: field_definition.size_bits,
      data_type: Atom.to_string(field_definition.data_type),
      engineering_unit: field_definition.engineering_unit
    }
  end

  defp raw_evidence(%RawEvidence{} = raw_evidence) do
    %{
      evidence_id: raw_evidence.evidence_id,
      mission_id: raw_evidence.mission_id,
      source_endpoint_ref: raw_evidence.source_endpoint_ref,
      spacecraft_id: raw_evidence.spacecraft_id,
      protocol_family: Atom.to_string(raw_evidence.protocol_family),
      direction: Atom.to_string(raw_evidence.direction),
      source_time: iso8601(raw_evidence.source_time),
      receipt_time: iso8601(raw_evidence.receipt_time),
      source_ref: raw_evidence.source_ref,
      raw_hex: hex(raw_evidence.raw),
      raw_size_bytes: byte_size(raw_evidence.raw),
      metadata: raw_evidence.metadata
    }
  end

  defp packet_record(%PacketRecord{} = packet_record) do
    %{
      packet_id: packet_record.packet_id,
      evidence_id: packet_record.evidence_id,
      mission_id: packet_record.mission_id,
      source_endpoint_ref: packet_record.source_endpoint_ref,
      spacecraft_id: packet_record.spacecraft_id,
      protocol_family: Atom.to_string(packet_record.protocol_family),
      packet_kind: Atom.to_string(packet_record.packet_kind),
      apid: packet_record.apid,
      sequence_flags: packet_record.sequence_flags,
      sequence_count: packet_record.sequence_count,
      secondary_header: packet_record.secondary_header?,
      packet_data_hex: hex(packet_record.packet_data),
      packet_data_size_bytes: byte_size(packet_record.packet_data),
      source_time: iso8601(packet_record.source_time),
      receipt_time: iso8601(packet_record.receipt_time),
      provenance: JsonDocument.encode(packet_record.provenance)
    }
  end

  defp transfer_frame_record(%TransferFrameRecord{} = transfer_frame_record) do
    %{
      frame_record_id: transfer_frame_record.frame_record_id,
      evidence_id: transfer_frame_record.evidence_id,
      mission_id: transfer_frame_record.mission_id,
      source_endpoint_ref: transfer_frame_record.source_endpoint_ref,
      spacecraft_id: transfer_frame_record.spacecraft_id,
      protocol_family: Atom.to_string(transfer_frame_record.protocol_family),
      direction: Atom.to_string(transfer_frame_record.direction),
      scid: transfer_frame_record.scid,
      vcid: transfer_frame_record.vcid,
      map_id: transfer_frame_record.map_id,
      frame_seq: transfer_frame_record.frame_seq,
      raw_frame_offset_bytes: transfer_frame_record.raw_frame_offset_bytes,
      raw_frame_length_bytes: transfer_frame_record.raw_frame_length_bytes,
      payload_length_bytes: transfer_frame_record.payload_length_bytes,
      first_header_pointer: transfer_frame_record.first_header_pointer,
      quality: maybe_atom_to_string(transfer_frame_record.quality),
      source_time: iso8601(transfer_frame_record.source_time),
      receipt_time: iso8601(transfer_frame_record.receipt_time),
      metadata: JsonDocument.encode(transfer_frame_record.metadata)
    }
  end

  defp protocol_anomaly(%ProtocolAnomaly{} = protocol_anomaly) do
    %{
      anomaly_id: protocol_anomaly.anomaly_id,
      evidence_id: protocol_anomaly.evidence_id,
      mission_id: protocol_anomaly.mission_id,
      source_endpoint_ref: protocol_anomaly.source_endpoint_ref,
      spacecraft_id: protocol_anomaly.spacecraft_id,
      protocol_family: Atom.to_string(protocol_anomaly.protocol_family),
      direction: Atom.to_string(protocol_anomaly.direction),
      anomaly_kind: Atom.to_string(protocol_anomaly.anomaly_kind),
      scid: protocol_anomaly.scid,
      vcid: protocol_anomaly.vcid,
      map_id: protocol_anomaly.map_id,
      frame_seq: protocol_anomaly.frame_seq,
      raw_frame_offset_bytes: protocol_anomaly.raw_frame_offset_bytes,
      raw_frame_length_bytes: protocol_anomaly.raw_frame_length_bytes,
      recorded_at: iso8601(protocol_anomaly.recorded_at),
      metadata: JsonDocument.encode(protocol_anomaly.metadata)
    }
  end

  defp dispatch_decision(%DispatchDecision{} = dispatch_decision) do
    %{
      dispatch_decision_id: dispatch_decision.dispatch_decision_id,
      packet_id: dispatch_decision.packet_id,
      evidence_id: dispatch_decision.evidence_id,
      binding_set_id: dispatch_decision.binding_set_id,
      binding_set_version: dispatch_decision.binding_set_version,
      status: Atom.to_string(dispatch_decision.status),
      matched_rule_ids: dispatch_decision.matched_rule_ids,
      anomalies: JsonDocument.encode(dispatch_decision.anomalies),
      work_items: Enum.map(dispatch_decision.work_items, &work_item/1)
    }
  end

  defp work_item(%WorkItem{} = work_item) do
    %{
      binding_rule_id: work_item.binding_rule_id,
      capability_instance_id: work_item.capability_instance_id,
      handler_key: Atom.to_string(work_item.handler_key)
    }
  end

  defp runtime_output(%Sample{} = sample) do
    telemetry_sample(sample)
    |> Map.put(:output_kind, "telemetry_sample")
  end

  defp runtime_output(output) do
    %{
      output_kind: "generic",
      output_document: JsonDocument.encode(output)
    }
  end

  defp catalog_selector_input(%SelectorInput{} = selector_input) do
    %{
      selector_input_id: selector_input.selector_input_id,
      packet_definition_id: selector_input.packet_definition_id,
      capability_instance_id: selector_input.capability_instance_id,
      capability_family_key: Atom.to_string(selector_input.capability_family_key),
      selector: %{
        scope: %{
          target_scope: Atom.to_string(selector_input.selector.scope.target_scope),
          source_endpoint_ref: selector_input.selector.scope.source_endpoint_ref
        },
        match: %{
          packet_kind: maybe_atom_to_string(selector_input.selector.match.packet_kind),
          apid: selector_input.selector.match.apid
        }
      }
    }
  end

  defp contact_path(%Path{} = path) do
    %{
      path_id: path.path_id,
      direction: maybe_atom_to_string(path.direction),
      selection_role: maybe_atom_to_string(path.selection_role),
      source_endpoint_ref: path.source_endpoint_ref,
      provider_path_ref: path.provider_path_ref,
      provider_bindings: Enum.map(path.provider_bindings, &provider_binding/1),
      transport_bindings: Enum.map(path.transport_bindings, &transport_binding/1),
      metadata: path.metadata
    }
  end

  defp provider_binding(%ProviderBinding{} = provider_binding) do
    %{
      provider_binding_id: provider_binding.provider_binding_id,
      adapter_key: maybe_atom_to_string(provider_binding.adapter_key),
      configuration: json_value(provider_binding.configuration),
      metadata: json_value(provider_binding.metadata)
    }
  end

  defp transport_binding(%TransportBinding{} = transport_binding) do
    %{
      transport_binding_id: transport_binding.transport_binding_id,
      family_key: maybe_atom_to_string(transport_binding.family_key),
      target_scope: maybe_atom_to_string(transport_binding.target_scope),
      configuration: transport_binding.configuration,
      metadata: transport_binding.metadata
    }
  end

  defp provider_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      provider_binding_id: snapshot_value(snapshot, :provider_binding_id),
      adapter_key: snapshot_atom_string(snapshot, :adapter_key),
      direction: snapshot_atom_string(snapshot, :direction),
      mode: snapshot_atom_string(snapshot, :mode),
      host: snapshot_value(snapshot, :host),
      configured_port: snapshot_value(snapshot, :configured_port),
      port: snapshot_value(snapshot, :port),
      connected?: snapshot_value(snapshot, :connected?, false),
      ingress_protocol_family: snapshot_atom_string(snapshot, :ingress_protocol_family),
      fixed_message_bytes: snapshot_value(snapshot, :fixed_message_bytes),
      ingress_transport_binding_id: snapshot_value(snapshot, :ingress_transport_binding_id),
      source_ref: snapshot_value(snapshot, :source_ref),
      ingress_metadata: snapshot_json(snapshot, :ingress_metadata, %{}),
      uplink_bytes_sent: snapshot_value(snapshot, :uplink_bytes_sent, 0),
      uplink_payload_count: snapshot_value(snapshot, :uplink_payload_count, 0),
      downlink_bytes_received: snapshot_value(snapshot, :downlink_bytes_received, 0),
      downlink_message_count: snapshot_value(snapshot, :downlink_message_count, 0),
      last_delivery_at: snapshot_iso8601(snapshot, :last_delivery_at),
      last_ingress_at: snapshot_iso8601(snapshot, :last_ingress_at),
      last_ingress_error: snapshot_value(snapshot, :last_ingress_error)
    }
  end

  defp transport_runtime_snapshot(snapshot) when is_map(snapshot) do
    %{
      mission_id: snapshot_value(snapshot, :mission_id),
      realized_contact_id: snapshot_value(snapshot, :realized_contact_id),
      path_id: snapshot_value(snapshot, :path_id),
      activation_id: snapshot_value(snapshot, :activation_id),
      binding_set_id: snapshot_value(snapshot, :binding_set_id),
      binding_set_version: snapshot_value(snapshot, :binding_set_version),
      capability_instance_id: snapshot_value(snapshot, :capability_instance_id),
      family_key: snapshot_atom_string(snapshot, :family_key),
      scope_ref: snapshot_value(snapshot, :scope_ref),
      partition_key: snapshot_value(snapshot, :partition_key),
      clock_mode: snapshot_atom_string(snapshot, :clock_mode),
      current_time: snapshot_iso8601(snapshot, :current_time),
      timer_count: snapshot_value(snapshot, :timer_count, 0),
      timers: snapshot_json(snapshot, :timers, []),
      state: snapshot_json(snapshot, :state, %{}),
      output_count: snapshot_value(snapshot, :output_count, 0),
      outputs: snapshot_json(snapshot, :outputs, [])
    }
  end

  defp scope_summary(scope_summary) do
    %{
      scope_id: scope_summary.scope_id,
      scope_kind: maybe_atom_to_string(scope_summary.scope_kind),
      scope_label: scope_summary.scope_label,
      spacecraft_id: scope_summary.spacecraft_id,
      total_points: scope_summary.total_points,
      violating_points: scope_summary.violating_points,
      normalized_state_counts: scope_summary.normalized_state_counts,
      worst_normalized_state: maybe_atom_to_string(scope_summary.worst_normalized_state),
      updated_at: iso8601(scope_summary.updated_at),
      point_buckets: point_buckets(scope_summary.point_buckets)
    }
  end

  defp point_buckets(point_buckets) when is_map(point_buckets) do
    %{
      red: Enum.map(Map.get(point_buckets, :red, []), &limit_event/1),
      yellow: Enum.map(Map.get(point_buckets, :yellow, []), &limit_event/1),
      green: Enum.map(Map.get(point_buckets, :green, []), &limit_event/1),
      blue: Enum.map(Map.get(point_buckets, :blue, []), &limit_event/1)
    }
  end

  defp limit_event(%LimitEvent{} = limit_event) do
    %{
      limit_event_id: limit_event.limit_event_id,
      mission_id: limit_event.mission_id,
      spacecraft_id: limit_event.spacecraft_id,
      point_id: limit_event.point_id,
      point_name: limit_event.point_name,
      source_sample_type: maybe_atom_to_string(limit_event.source_sample_type),
      sample_id: limit_event.sample_id,
      limit_definition_id: limit_event.limit_definition_id,
      limit_definition_version: limit_event.limit_definition_version,
      limit_set_name: limit_event.limit_set_name,
      evaluated_value: limit_event.evaluated_value,
      limit_state: maybe_atom_to_string(limit_event.limit_state),
      normalized_state: maybe_atom_to_string(limit_event.normalized_state),
      violation: limit_event.violation,
      generation_time: iso8601(limit_event.generation_time),
      receipt_time: iso8601(limit_event.receipt_time),
      provenance: limit_event.provenance
    }
  end

  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value

  defp snapshot_value(snapshot, key, default \\ nil) when is_map(snapshot) and is_atom(key) do
    case Map.fetch(snapshot, key) do
      {:ok, value} -> value
      :error -> Map.get(snapshot, Atom.to_string(key), default)
    end
  end

  defp snapshot_atom_string(snapshot, key, default \\ nil) do
    snapshot
    |> snapshot_value(key, default)
    |> maybe_atom_to_string()
  end

  defp snapshot_iso8601(snapshot, key, default \\ nil) do
    snapshot
    |> snapshot_value(key, default)
    |> iso8601()
  end

  defp snapshot_json(snapshot, key, default) do
    snapshot
    |> snapshot_value(key, default)
    |> json_value()
  end

  defp snapshot_list(snapshot, key, mapper, default \\ []) when is_function(mapper, 1) do
    snapshot
    |> snapshot_value(key, default)
    |> Enum.map(mapper)
  end

  defp json_value(%DateTime{} = datetime), do: iso8601(datetime)

  defp json_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {json_key(key), json_value(value)}
    end)
  end

  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key

  defp hex(binary) when is_binary(binary), do: Base.encode16(binary, case: :lower)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
