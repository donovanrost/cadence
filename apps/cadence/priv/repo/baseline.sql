--
-- PostgreSQL database dump
-- #718: schema from a fresh PostgreSQL 17 migration of develop b18137b61.
-- Ecto owns schema_migrations, so its table is intentionally omitted here.
-- Enum checks use their original IN form because PostgreSQL rewrites pg_dump's
-- ANY array casts on reload; this keeps the schema-only dump identical.
--


-- Dumped from database version 17.12 (Debian 17.12-1.pgdg13+1)
-- Dumped by pg_dump version 17.12 (Debian 17.12-1.pgdg13+1)

SET LOCAL statement_timeout = 0;
SET LOCAL lock_timeout = 0;
SET LOCAL idle_in_transaction_session_timeout = 0;
SET LOCAL client_encoding = 'UTF8';
SET LOCAL standard_conforming_strings = on;
SET LOCAL check_function_bodies = false;
SET LOCAL xmloption = content;
SET LOCAL client_min_messages = warning;
SET LOCAL row_security = off;

--
-- Name: cadence_decision_record_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_decision_record_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF cadence_decision_record_purge_allowed(current_database()) THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; END IF;
    RETURN NULL;
  END IF;
  RAISE EXCEPTION 'decision records are append-only: % on % refused', TG_OP, TG_TABLE_NAME
    USING ERRCODE = 'raise_exception';
END;
$$;


--
-- Name: cadence_decision_record_purge_allowed(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_decision_record_purge_allowed(database_name text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT coalesce(current_setting('cadence.decision_record_test_purge', true), '') = 'on'
     AND database_name LIKE 'cadence\_test%'
$$;


--
-- Name: cadence_enforce_frontend_release_artifact_size_cap(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_enforce_frontend_release_artifact_size_cap() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  total_size bigint;
BEGIN
  PERFORM 1
  FROM frontend_release_publications
  WHERE publication_id = NEW.release_publication_id
  FOR UPDATE;

  SELECT COALESCE(SUM(size), 0) + NEW.size
  INTO total_size
  FROM frontend_release_artifacts
  WHERE release_publication_id = NEW.release_publication_id;

  IF total_size > 100000000 THEN
    RAISE EXCEPTION 'frontend release artifact byte cap exceeded';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: cadence_guard_frontend_release_activation_control(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_guard_frontend_release_activation_control() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.cutover_epoch = 0 THEN
    IF NEW.cutover_epoch <> 1 OR NEW.cutover_at IS NULL THEN
      RAISE EXCEPTION 'frontend release activation control can only cut over from epoch zero to one';
    END IF;
  ELSE
    IF NEW.cutover_epoch <> OLD.cutover_epoch
       OR NEW.cutover_at IS DISTINCT FROM OLD.cutover_at
       OR NEW.legacy_catalog_publication_id IS DISTINCT FROM OLD.legacy_catalog_publication_id THEN
      RAISE EXCEPTION 'frontend release activation control is immutable after cutover';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: cadence_mission_scope_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_mission_scope_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'a mission''s mission_id and organization_id never change (mission %)',
      OLD.mission_id
      USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: cadence_reject_frontend_release_publication_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_reject_frontend_release_publication_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'frontend release publication tables are append-only';
END;
$$;


--
-- Name: cadence_require_frontend_release_catalog_generation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_require_frontend_release_catalog_generation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cutover bigint;
BEGIN
  SELECT cutover_epoch INTO cutover
  FROM frontend_release_activation_controls
  WHERE control_id = 1;

  IF cutover > 0 AND NOT EXISTS (
    SELECT 1 FROM frontend_release_catalog_generations
    WHERE catalog_publication_id = NEW.publication_id
  ) THEN
    RAISE EXCEPTION 'accepted frontend release catalog publication requires a generation after cutover';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: cadence_sync_organization_id_from_mission(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cadence_sync_organization_id_from_mission() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.mission_id IS NULL OR NEW.organization_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT missions.organization_id
  INTO NEW.organization_id
  FROM missions
  WHERE missions.mission_id = NEW.mission_id;

  RETURN NEW;
END;
$$;


--
-- Name: governed_packet_definition_field_fill_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.governed_packet_definition_field_fill_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.packet_definition_row_id IS DISTINCT FROM OLD.packet_definition_row_id
     OR NEW.field_id IS DISTINCT FROM OLD.field_id
     OR NEW.name IS DISTINCT FROM OLD.name
     OR NEW.offset_bits IS DISTINCT FROM OLD.offset_bits
     OR NEW.size_bits IS DISTINCT FROM OLD.size_bits
     OR NEW.data_type IS DISTINCT FROM OLD.data_type
     OR NEW.byte_order IS DISTINCT FROM OLD.byte_order
     OR NEW.engineering_unit IS DISTINCT FROM OLD.engineering_unit
     OR NEW.inserted_at IS DISTINCT FROM OLD.inserted_at
     OR (OLD.parameter_id IS NOT NULL AND NEW.parameter_id IS DISTINCT FROM OLD.parameter_id)
     OR (OLD.qualified_name IS NOT NULL AND NEW.qualified_name IS DISTINCT FROM OLD.qualified_name)
  THEN
    RAISE EXCEPTION 'governed_packet_definition_fields is immutable under its key except the #73 identity fill (#534)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: governed_packet_definition_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.governed_packet_definition_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION '% is immutable under its key (#534)', TG_TABLE_NAME;
END;
$$;


--
-- Name: governed_packet_definition_no_truncate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.governed_packet_definition_no_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION '% is immutable under its key (#534): TRUNCATE refused', TG_TABLE_NAME;
END;
$$;


--
-- Name: mission_model_composition_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mission_model_composition_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION '% is immutable (#541)', TG_TABLE_NAME;
END;
$$;


SET LOCAL default_tablespace = '';

SET LOCAL default_table_access_method = heap;

--
-- Name: account_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_events (
    account_event_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp without time zone NOT NULL
);


--
-- Name: activation_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_decisions (
    activation_decision_id character varying(255) NOT NULL,
    activation_request_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    decision character varying(255) NOT NULL,
    actor_kind character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    reason text,
    decided_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT activation_decisions_decision_check CHECK ((decision IN ('approved', 'rejected', 'withdrawn'))),
    CONSTRAINT activation_decisions_reason_unless_approved CHECK (((reason IS NOT NULL) OR ((decision)::text = 'approved'::text)))
);


--
-- Name: activation_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_executions (
    activation_execution_id character varying(255) NOT NULL,
    activation_request_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    executor_actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    activation_id character varying(255),
    generation bigint,
    binding_set_content_sha256 character varying(255) NOT NULL,
    error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT activation_executions_status_check CHECK ((status IN ('in_progress', 'succeeded', 'failed')))
);


--
-- Name: activation_fleet_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_fleet_entries (
    mission_id character varying(255) NOT NULL,
    entry_sha256 character varying(255) NOT NULL,
    organization_id character varying(255),
    entry jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: activation_fleet_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_fleet_members (
    mission_id character varying(255) NOT NULL,
    fleet_sha256 character varying(255) NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    organization_id character varying(255),
    entry_sha256 character varying(255) NOT NULL,
    source_endpoint_ids character varying(255)[] NOT NULL,
    commanding_enabled boolean NOT NULL,
    catalog_revision_id character varying(255) NOT NULL,
    mission_model_sha256 character varying(255) NOT NULL
);


--
-- Name: activation_fleets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_fleets (
    mission_id character varying(255) NOT NULL,
    fleet_sha256 character varying(255) NOT NULL,
    organization_id character varying(255),
    spacecraft_count integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: activation_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_requests (
    activation_request_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    binding_set_content_sha256 character varying(255) NOT NULL,
    change_class character varying(255) NOT NULL,
    state character varying(255) NOT NULL,
    requester_actor_kind character varying(255) NOT NULL,
    requester_actor_id character varying(255) NOT NULL,
    requester_actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    policy_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    decided_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    superseded_by character varying(255),
    superseded_at timestamp without time zone,
    CONSTRAINT activation_requests_state_check CHECK ((state IN ('approval_pending', 'approved', 'rejected', 'withdrawn', 'superseded')))
);


--
-- Name: active_limit_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_limit_definitions (
    definition_activation_key character varying(255) NOT NULL,
    limit_definition_lifecycle_event_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    point_id character varying(255) NOT NULL,
    limit_set_name character varying(255) NOT NULL,
    scope_type character varying(255),
    scope_ref character varying(255),
    realm character varying(255),
    event_type character varying(255) NOT NULL,
    limit_definition_id character varying(255) NOT NULL,
    limit_definition_version integer NOT NULL,
    previous_limit_definition_id character varying(255),
    previous_limit_definition_version integer,
    active_from timestamp without time zone NOT NULL,
    active_to timestamp without time zone,
    reason character varying(255),
    last_seen_at timestamp without time zone NOT NULL,
    transition_count integer DEFAULT 1 NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: alarm_episode_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alarm_episode_events (
    event_id character varying(255) NOT NULL,
    episode_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    actor jsonb,
    at timestamp without time zone NOT NULL,
    source_ref character varying(255),
    payload jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: alarm_episodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alarm_episodes (
    episode_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    spacecraft_scope_id character varying(255) NOT NULL,
    source character varying(255) NOT NULL,
    subject_key character varying(255) NOT NULL,
    parameter_ref character varying(255) NOT NULL,
    point_name character varying(255),
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    severity character varying(255) NOT NULL,
    peak_severity character varying(255) NOT NULL,
    source_state character varying(255) NOT NULL,
    state character varying(255) NOT NULL,
    opened_at timestamp without time zone NOT NULL,
    opened_by_ref character varying(255),
    first_value jsonb,
    last_value jsonb,
    last_observed_at timestamp without time zone NOT NULL,
    last_evaluated_at timestamp without time zone NOT NULL,
    cleared_at timestamp without time zone,
    cleared_by_ref character varying(255),
    cleared_unacknowledged boolean DEFAULT false NOT NULL,
    acknowledged_at timestamp without time zone,
    acknowledged_by jsonb,
    assignee jsonb,
    assigned_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: application_dispatch_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_dispatch_decisions (
    dispatch_decision_id character varying(255) NOT NULL,
    packet_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    status character varying(255) NOT NULL,
    matched_rule_ids jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    anomalies jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: application_dispatch_work_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_dispatch_work_items (
    id bigint NOT NULL,
    dispatch_decision_id character varying(255) NOT NULL,
    binding_rule_id character varying(255) NOT NULL,
    handler_key character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: application_dispatch_work_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.application_dispatch_work_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: application_dispatch_work_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.application_dispatch_work_items_id_seq OWNED BY public.application_dispatch_work_items.id;


--
-- Name: application_installation_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_installation_events (
    application_installation_event_id character varying(255) NOT NULL,
    application_installation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    scope_kind character varying(255) NOT NULL,
    scope_id character varying(255) NOT NULL,
    application_key character varying(255) NOT NULL,
    event_type character varying(255) NOT NULL,
    previous_lifecycle_state character varying(255),
    current_lifecycle_state character varying(255) NOT NULL,
    previous_application_version integer,
    current_application_version integer NOT NULL,
    previous_configuration_version integer,
    current_configuration_version integer,
    actor_id character varying(255) NOT NULL,
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT application_installation_events_type_check CHECK ((event_type IN ('installed', 'reinstalled', 'enabled', 'disabled', 'uninstalled', 'application_upgraded', 'configuration_updated')))
);


--
-- Name: application_installations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_installations (
    application_installation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    scope_kind character varying(255) NOT NULL,
    scope_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    application_key character varying(255) NOT NULL,
    application_version integer NOT NULL,
    configuration_kind character varying(255),
    configuration_id character varying(255),
    configuration_version integer,
    lifecycle_state character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT application_installations_configuration_ref_check CHECK ((((configuration_kind IS NULL) AND (configuration_id IS NULL) AND (configuration_version IS NULL)) OR ((configuration_kind IS NOT NULL) AND (configuration_id IS NOT NULL) AND (configuration_version > 0)))),
    CONSTRAINT application_installations_lifecycle_state_check CHECK ((lifecycle_state IN ('installed', 'disabled', 'uninstalled'))),
    CONSTRAINT application_installations_scope_kind_check CHECK ((scope_kind IN ('mission', 'spacecraft'))),
    CONSTRAINT application_installations_scope_ref_check CHECK (((((scope_kind)::text = 'mission'::text) AND ((scope_id)::text = (mission_id)::text) AND (spacecraft_id IS NULL)) OR (((scope_kind)::text = 'spacecraft'::text) AND ((scope_id)::text = (spacecraft_id)::text) AND (spacecraft_id IS NOT NULL)))),
    CONSTRAINT application_installations_version_check CHECK ((application_version > 0))
);


--
-- Name: application_packet_binding_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_packet_binding_configurations (
    packet_binding_configuration_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    application_installation_id character varying(255) NOT NULL,
    application_key character varying(255) NOT NULL,
    application_version integer NOT NULL,
    capability_family_key character varying(255) NOT NULL,
    input_id character varying(255) NOT NULL,
    input_version integer NOT NULL,
    configuration_version integer DEFAULT 1 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    applied_binding_set_id character varying(255),
    applied_binding_set_version integer,
    applied_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT application_packet_binding_configurations_versions_check CHECK (((application_version > 0) AND (input_version > 0) AND (configuration_version > 0)))
);


--
-- Name: application_packet_binding_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_packet_binding_resources (
    packet_binding_resource_id character varying(255) NOT NULL,
    packet_binding_id character varying(255) NOT NULL,
    resource_id character varying(255) NOT NULL,
    resource_kind character varying(255) NOT NULL,
    path character varying(255),
    data_type character varying(255),
    offset_bits integer,
    size_bits integer,
    role character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT application_packet_resources_kind_check CHECK ((resource_kind IN ('whole_packet', 'field', 'binary_region'))),
    CONSTRAINT application_packet_resources_role_check CHECK ((role IN ('primary', 'context')))
);


--
-- Name: application_packet_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_packet_bindings (
    packet_binding_id character varying(255) NOT NULL,
    packet_binding_configuration_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    catalog_revision_id character varying(255),
    mission_model_revision_id character varying(255),
    packet_id character varying(255),
    packet_model_content_sha256 character varying(255),
    packet_name character varying(255) NOT NULL,
    apid integer NOT NULL,
    selector jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT application_packet_bindings_apid_check CHECK (((apid >= 0) AND (apid <= 2047)))
);


--
-- Name: automation_grant_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_grant_decisions (
    automation_grant_decision_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    automation_grant_id character varying(255) NOT NULL,
    decision character varying(255) NOT NULL,
    actor_kind character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    reason text,
    decided_at timestamp without time zone NOT NULL,
    digest character varying(255),
    previous_digest character varying(255),
    policy_document jsonb,
    separated_from character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    admin_mode boolean DEFAULT false NOT NULL,
    CONSTRAINT automation_grant_decisions_decision CHECK ((decision IN ('proposed', 'not_required', 'approved', 'rejected', 'revoked', 'narrowed', 'withdrawn', 'suspended', 'resumed')))
);


--
-- Name: automation_grant_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_grant_operations (
    automation_grant_operation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    operation_id character varying(255) NOT NULL,
    automation_grant_id character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    request_sha256 character varying(255) NOT NULL,
    response_status integer NOT NULL,
    response_document jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: automation_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_grants (
    automation_grant_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    service_identity_id character varying(255) NOT NULL,
    fleet_planning_policy_id character varying(255) NOT NULL,
    fleet_planning_policy_version integer NOT NULL,
    allowed_actions character varying(255)[] NOT NULL,
    maximum_horizon_seconds integer NOT NULL,
    maximum_contacts integer NOT NULL,
    maximum_estimated_cost_micros bigint,
    currency character varying(255),
    maximum_execution_concurrency integer NOT NULL,
    valid_from timestamp without time zone,
    valid_until timestamp without time zone,
    lifecycle_state character varying(255) NOT NULL,
    approved_by character varying(255),
    approved_at timestamp without time zone,
    approval_reason text NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    revoked_by character varying(255),
    revoked_at timestamp without time zone,
    revocation_reason text DEFAULT ''::text NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    validity_seconds integer,
    proposed_by character varying(255),
    proposed_at timestamp without time zone,
    proposal_expires_at timestamp without time zone,
    rejected_by character varying(255),
    rejected_at timestamp without time zone,
    rejection_reason character varying(255),
    withdrawn_by character varying(255),
    withdrawn_at timestamp without time zone,
    replaces_grant_id character varying(255),
    approval_policy jsonb,
    legacy_issue boolean DEFAULT false NOT NULL,
    suspended_by character varying(255),
    suspended_at timestamp without time zone,
    suspension_revision character varying(255),
    suspension_level character varying(255),
    resumed_by character varying(255),
    resumed_at timestamp without time zone,
    CONSTRAINT automation_grants_bounds_positive CHECK (((maximum_horizon_seconds > 0) AND (maximum_contacts > 0) AND (maximum_execution_concurrency > 0) AND ((maximum_estimated_cost_micros IS NULL) OR (maximum_estimated_cost_micros >= 0)))),
    CONSTRAINT automation_grants_cost_currency_check CHECK (((maximum_estimated_cost_micros IS NULL) = (currency IS NULL))),
    CONSTRAINT automation_grants_policy_version_positive CHECK ((fleet_planning_policy_version > 0)),
    CONSTRAINT automation_grants_state_check CHECK ((lifecycle_state IN ('proposed', 'active', 'suspended', 'rejected', 'revoked', 'withdrawn'))),
    CONSTRAINT automation_grants_state_shape CHECK (((proposed_by IS NOT NULL) AND (proposed_at IS NOT NULL) AND (proposal_expires_at IS NOT NULL) AND (validity_seconds > 0) AND ((((lifecycle_state)::text = 'proposed'::text) AND (approved_by IS NULL) AND (approved_at IS NULL) AND (valid_from IS NULL) AND (revoked_by IS NULL) AND (rejected_by IS NULL) AND (withdrawn_by IS NULL)) OR (((lifecycle_state)::text = 'active'::text) AND (approved_by IS NOT NULL) AND (approved_at IS NOT NULL) AND (valid_from IS NOT NULL) AND (revoked_by IS NULL) AND (revoked_at IS NULL) AND (rejected_by IS NULL) AND (withdrawn_by IS NULL)) OR (((lifecycle_state)::text = 'suspended'::text) AND (approved_by IS NOT NULL) AND (approved_at IS NOT NULL) AND (valid_from IS NOT NULL) AND (suspended_by IS NOT NULL) AND (suspended_at IS NOT NULL) AND (revoked_by IS NULL) AND (revoked_at IS NULL) AND (rejected_by IS NULL) AND (withdrawn_by IS NULL)) OR (((lifecycle_state)::text = 'revoked'::text) AND (approved_by IS NOT NULL) AND (valid_from IS NOT NULL) AND (revoked_by IS NOT NULL) AND (revoked_at IS NOT NULL)) OR (((lifecycle_state)::text = 'rejected'::text) AND (approved_by IS NULL) AND (rejected_by IS NOT NULL) AND (rejected_at IS NOT NULL) AND (COALESCE(TRIM(BOTH FROM rejection_reason), ''::text) <> ''::text)) OR (((lifecycle_state)::text = 'withdrawn'::text) AND (approved_by IS NULL) AND (withdrawn_by IS NOT NULL) AND (withdrawn_at IS NOT NULL))))),
    CONSTRAINT automation_grants_validity_check CHECK ((((valid_from IS NULL) AND (valid_until IS NULL)) OR ((valid_from IS NOT NULL) AND (valid_until IS NOT NULL) AND (valid_from < valid_until))))
);


--
-- Name: background_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.background_jobs (
    job_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    job_type character varying(255) NOT NULL,
    run_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: booking_resolutions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booking_resolutions (
    booking_resolution_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    contact_plan_execution_item_id character varying(255) NOT NULL,
    provider_reservation_id character varying(255) NOT NULL,
    provider_contact_ref character varying(255),
    scheduled_contact_id character varying(255),
    spacecraft_id character varying(255) NOT NULL,
    ground_station_ref character varying(255),
    provider_id character varying(255) NOT NULL,
    starts_at timestamp without time zone NOT NULL,
    ends_at timestamp without time zone NOT NULL,
    action character varying(255) NOT NULL,
    outcome character varying(255) NOT NULL,
    provider_reference character varying(255),
    note text NOT NULL,
    actor_document jsonb NOT NULL,
    provider_answer_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    conflict character varying(255),
    conflict_state character varying(255),
    conflict_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    conflict_raised_at timestamp without time zone,
    conflict_acknowledged_at timestamp without time zone,
    conflict_acknowledged_by jsonb,
    conflict_resolved_at timestamp without time zone,
    conflict_resolved_by jsonb,
    conflict_resolution_action character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: catalog_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_artifacts (
    artifact_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    catalog_database_id character varying(255),
    catalog_family character varying(255) NOT NULL,
    artifact_name character varying(255) NOT NULL,
    format_key character varying(255) NOT NULL,
    format_version character varying(255),
    media_type character varying(255),
    source_artifact jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    uploaded_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    uploaded_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: catalog_databases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_databases (
    catalog_database_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    description character varying(255),
    catalog_family character varying(255) NOT NULL,
    default_importer_key character varying(255),
    created_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: catalog_import_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_import_runs (
    import_run_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    catalog_database_id character varying(255),
    artifact_id character varying(255) NOT NULL,
    catalog_family character varying(255) NOT NULL,
    importer_key character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    imported_definition_count integer DEFAULT 0 NOT NULL,
    diagnostics jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    result_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    failure_reason jsonb,
    requested_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    importer_version integer DEFAULT 1 NOT NULL
);


--
-- Name: catalog_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_revisions (
    catalog_revision_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    catalog_database_id character varying(255) NOT NULL,
    revision_number integer NOT NULL,
    revision_label character varying(255) NOT NULL,
    catalog_family character varying(255) NOT NULL,
    artifact_id character varying(255) NOT NULL,
    import_run_id character varying(255) NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    created_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    notes character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    mission_model_layer_id character varying(255),
    mission_model_revision_id character varying(255)
);


--
-- Name: combined_downlink_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.combined_downlink_records (
    merged_record_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    observation_key character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    selected_path_id character varying(255) NOT NULL,
    selected_observation_id character varying(255) NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    selected_reason character varying(255) NOT NULL,
    observed_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: command_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_approvals (
    command_approval_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    command_request_id character varying(255) NOT NULL,
    decision character varying(255) NOT NULL,
    decided_by_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    decided_at timestamp without time zone NOT NULL,
    reason text,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    subject_digest character varying(255) NOT NULL,
    separated_from character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    admin_mode boolean NOT NULL,
    CONSTRAINT command_approvals_decision_check CHECK ((decision IN ('approved', 'rejected', 'not_required'))),
    CONSTRAINT command_approvals_subject_digest_check CHECK (((subject_digest)::text ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: command_drafts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_drafts (
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    revision integer NOT NULL,
    document jsonb NOT NULL,
    catalog_revision_id character varying(255),
    saved_at timestamp without time zone NOT NULL
);


--
-- Name: command_group_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_group_events (
    event_id character varying(255) NOT NULL,
    command_group_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    actor_document jsonb,
    at timestamp without time zone NOT NULL,
    payload_document jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: command_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_groups (
    command_group_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    state character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    log_entry text,
    requested_by_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    requested_approver_user_id character varying(255),
    operation_id character varying(255),
    sent_back_from character varying(255),
    target_query_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    targets_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    resolved_at timestamp without time zone NOT NULL,
    commands_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    release_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    basis_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    policy_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    preflight_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    member_count integer NOT NULL,
    decided_by_document jsonb,
    decided_at timestamp without time zone,
    decision_document jsonb,
    aborted_by_document jsonb,
    aborted_at timestamp without time zone,
    abort_reason text,
    abort_result_document jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: command_queue_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_queue_entries (
    command_queue_entry_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    command_request_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255) NOT NULL,
    queue_lane_key character varying(255) NOT NULL,
    priority integer DEFAULT 3 NOT NULL,
    queue_sequence bigint NOT NULL,
    not_before timestamp without time zone,
    expires_at timestamp without time zone,
    lifecycle_state character varying(255) NOT NULL,
    enqueued_by_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    enqueued_at timestamp without time zone NOT NULL,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    active_release_attempt_id character varying(255)
);


--
-- Name: command_release_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_release_attempts (
    command_release_attempt_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    command_queue_entry_id character varying(255) NOT NULL,
    command_request_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    path_id character varying(255),
    transport_binding_id character varying(255),
    mission_model_revision_id character varying(255) NOT NULL,
    command_id character varying(255) NOT NULL,
    command_name character varying(255),
    layout_kind character varying(255),
    preferred_uplink_service character varying(255),
    apid integer,
    service_type integer,
    service_subtype integer,
    opcode_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    encoded_binary_base64 text,
    encoded_size_bytes integer,
    lifecycle_state character varying(255) NOT NULL,
    failure_reason text,
    released_by_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    attempted_at timestamp without time zone NOT NULL,
    released_at timestamp without time zone,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    verification_state character varying(255),
    resolution_evidence jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: command_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_requests (
    command_request_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255) NOT NULL,
    mission_model_revision_id character varying(255) NOT NULL,
    command_id character varying(255) NOT NULL,
    command_name character varying(255) NOT NULL,
    command_display_name character varying(255),
    lifecycle_state character varying(255) NOT NULL,
    priority integer DEFAULT 3 NOT NULL,
    not_before timestamp without time zone,
    expires_at timestamp without time zone,
    requested_by_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_command_stage_id character varying(255),
    source_staged_command_item_id character varying(255),
    argument_values_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    resolved_argument_values_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    significance character varying(255),
    critical boolean DEFAULT false NOT NULL,
    hazardous boolean DEFAULT false NOT NULL,
    subsystem character varying(255),
    group_name character varying(255),
    preferred_uplink_service character varying(255),
    release_policy_hint character varying(255),
    apid integer,
    service_type integer,
    service_subtype integer,
    opcode_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    verification_state character varying(255),
    command_group_id character varying(255),
    group_target_index integer,
    group_position integer
);


--
-- Name: command_stages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_stages (
    command_stage_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    stage_name character varying(255) NOT NULL,
    description text,
    owner_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    visibility character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: command_verifier_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.command_verifier_instances (
    command_verifier_instance_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    command_request_id character varying(255) NOT NULL,
    command_release_attempt_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255) NOT NULL,
    mission_model_revision_id character varying(255) NOT NULL,
    command_id character varying(255) NOT NULL,
    command_name character varying(255),
    verifier_id character varying(255) NOT NULL,
    verifier_name character varying(255) NOT NULL,
    phase character varying(255) NOT NULL,
    severity character varying(255),
    success_criteria_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    failure_criteria_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    delay_until timestamp without time zone,
    timeout_at timestamp without time zone,
    lifecycle_state character varying(255) NOT NULL,
    matched_record_id character varying(255),
    matched_at timestamp without time zone,
    failure_reason text,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    matched_record_kind character varying(255)
);


--
-- Name: comms_ground_stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comms_ground_stations (
    ground_station_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    provider character varying(255),
    region character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    code character varying(255)
);


--
-- Name: comms_routing_rule_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comms_routing_rule_events (
    routing_rule_event_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    routing_rule_id character varying(255) NOT NULL,
    event_type character varying(255) NOT NULL,
    actor_id character varying(255),
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: comms_routing_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comms_routing_rules (
    routing_rule_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    purpose_label character varying(255) NOT NULL,
    direction character varying(255) NOT NULL,
    transport_id character varying(255) NOT NULL,
    transport_version integer NOT NULL,
    provider_path_ref character varying(255),
    role character varying(255) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    materialized_link_assignment_id character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    id bigint NOT NULL,
    origin character varying(255) DEFAULT 'legacy'::character varying NOT NULL,
    profile_rule_id character varying(255),
    spacecraft_type_id character varying(255),
    spacecraft_type_version integer,
    ground_station_id character varying(255),
    leg_direction character varying(255)
);


--
-- Name: comms_routing_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comms_routing_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comms_routing_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comms_routing_rules_id_seq OWNED BY public.comms_routing_rules.id;


--
-- Name: comms_transports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comms_transports (
    transport_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    transport_kind character varying(255) NOT NULL,
    direction_capability character varying(255) NOT NULL,
    adapter_key character varying(255) NOT NULL,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    materialized_provider_profile_id character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    origin character varying(255) DEFAULT 'direct'::character varying NOT NULL,
    mission_provider_id character varying(255),
    mission_provider_version integer,
    service_profile_ref jsonb,
    delivery_profile_ref jsonb,
    provider_configuration_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    ground_station_id character varying(255)
);


--
-- Name: contact_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_actions (
    contact_action_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    scheduled_contact_id character varying(255),
    realized_contact_id character varying(255),
    action_kind character varying(255) NOT NULL,
    reason character varying(255),
    actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: contact_link_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_link_assignments (
    link_assignment_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255) NOT NULL,
    path_template_id character varying(255) NOT NULL,
    path_template_version integer DEFAULT 1 NOT NULL,
    direction character varying(255) NOT NULL,
    selection_role character varying(255) NOT NULL,
    provider_path_ref character varying(255),
    provider_profile_ref_documents jsonb DEFAULT '{}'::jsonb NOT NULL,
    transport_profile_ref_documents jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: contact_opportunity_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_opportunity_snapshots (
    contact_opportunity_snapshot_id character varying(255) NOT NULL,
    contact_planning_run_id character varying(255) NOT NULL,
    contact_planning_search_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_requirement_id character varying(255) NOT NULL,
    contact_requirement_version integer NOT NULL,
    provider_opportunity_ref character varying(255) NOT NULL,
    starts_at timestamp without time zone NOT NULL,
    ends_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    availability character varying(255) NOT NULL,
    estimated_capacity_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    synthetic boolean DEFAULT false NOT NULL,
    normalized_opportunity_document jsonb NOT NULL,
    evaluation_document jsonb NOT NULL,
    eligible boolean NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    captured_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_opportunity_snapshots_time_check CHECK ((starts_at < ends_at))
);


--
-- Name: contact_pass_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_pass_results (
    provider_reservation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    provider_id character varying(255) NOT NULL,
    scheduled_contact_id character varying(255),
    realized_contact_id character varying(255),
    spacecraft_id character varying(255) NOT NULL,
    ground_station_ref character varying(255),
    antenna_ref character varying(255),
    contact_plan_id character varying(255),
    contact_plan_version integer,
    planned_aos timestamp without time zone NOT NULL,
    planned_los timestamp without time zone NOT NULL,
    actual_aos timestamp without time zone,
    actual_los timestamp without time zone,
    planned_seconds integer NOT NULL,
    flown_seconds integer,
    planned_bytes bigint,
    provider_bytes bigint,
    provider_frames bigint,
    provider_packets bigint,
    received_bytes bigint,
    received_frames bigint,
    observations jsonb DEFAULT '{}'::jsonb NOT NULL,
    outcome character varying(255) NOT NULL,
    cause character varying(255),
    cause_source character varying(255),
    owner character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    disputable boolean DEFAULT false NOT NULL,
    provider_reported_at timestamp without time zone,
    provider_revision integer,
    closed_at timestamp without time zone,
    result_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_pass_results_outcome_check CHECK ((outcome IN ('realized', 'partial', 'missed', 'failed', 'canceled', 'pending_report'))),
    CONSTRAINT contact_pass_results_owner_check CHECK ((owner IN ('provider', 'us', 'weather', 'unknown')))
);


--
-- Name: contact_path_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_path_templates (
    path_template_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    path_id character varying(255) NOT NULL,
    direction character varying(255) NOT NULL,
    selection_role character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    provider_path_ref character varying(255),
    provider_profile_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    transport_profile_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL,
    provider_profile_ref_documents jsonb DEFAULT '{}'::jsonb NOT NULL,
    transport_profile_ref_documents jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: contact_plan_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_approvals (
    contact_plan_approval_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    decision character varying(255) NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    reason text,
    actor_id character varying(255) NOT NULL,
    actor_document jsonb NOT NULL,
    decided_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    actor_kind character varying(255) DEFAULT 'user'::character varying NOT NULL,
    automation_grant_id character varying(255),
    automation_grant_content_sha256 character varying(255),
    exceptions_document jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    policy_document jsonb,
    separated_from text[] DEFAULT ARRAY[]::text[] NOT NULL,
    skipped_document jsonb[],
    CONSTRAINT contact_plan_approvals_actor_kind_check CHECK ((actor_kind IN ('user', 'service'))),
    CONSTRAINT contact_plan_approvals_automation_shape CHECK (((((actor_kind)::text = 'user'::text) AND (automation_grant_id IS NULL) AND (automation_grant_content_sha256 IS NULL)) OR (((actor_kind)::text = 'service'::text) AND (automation_grant_id IS NOT NULL) AND (automation_grant_content_sha256 IS NOT NULL)))),
    CONSTRAINT contact_plan_approvals_decision_check CHECK ((decision IN ('approved', 'rejected')))
);


--
-- Name: contact_plan_execution_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_execution_items (
    contact_plan_execution_item_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    contact_opportunity_snapshot_id character varying(255) NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    provider_reservation_id character varying(255),
    attempt_count integer DEFAULT 0 NOT NULL,
    last_error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_plan_execution_items_attempts_check CHECK ((attempt_count >= 0)),
    CONSTRAINT contact_plan_execution_items_state_check CHECK ((lifecycle_state IN ('pending', 'requesting', 'reserved', 'uncertain', 'rejected', 'failed')))
);


--
-- Name: contact_plan_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_operations (
    contact_plan_operation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    operation_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    request_sha256 character varying(255) NOT NULL,
    response_status integer NOT NULL,
    response_document jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: contact_plan_opportunity_refs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_opportunity_refs (
    contact_plan_opportunity_ref_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    contact_opportunity_snapshot_id character varying(255) NOT NULL,
    disposition character varying(255) NOT NULL,
    selection_order integer NOT NULL,
    reason_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT contact_plan_opportunity_refs_disposition_check CHECK ((disposition IN ('selected', 'locked', 'rejected'))),
    CONSTRAINT contact_plan_opportunity_refs_order_check CHECK ((selection_order >= 0))
);


--
-- Name: contact_plan_requirement_refs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_requirement_refs (
    contact_plan_requirement_ref_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    contact_requirement_id character varying(255) NOT NULL,
    contact_requirement_version integer NOT NULL
);


--
-- Name: contact_plan_run_refs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_run_refs (
    contact_plan_run_ref_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    contact_planning_run_id character varying(255) NOT NULL
);


--
-- Name: contact_plan_submissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_submissions (
    contact_plan_submission_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    contact_plan_version integer NOT NULL,
    round integer NOT NULL,
    actor_document jsonb NOT NULL,
    note text,
    unchanged boolean DEFAULT false NOT NULL,
    acknowledgements_document jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    submitted_at timestamp without time zone NOT NULL,
    policy_document jsonb
);


--
-- Name: contact_plan_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plan_versions (
    contact_plan_version_id character varying(255) NOT NULL,
    contact_plan_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    requirement_refs_document jsonb NOT NULL,
    planning_run_refs_document jsonb NOT NULL,
    selected_snapshot_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    rejected_snapshot_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    coverage_document jsonb NOT NULL,
    conflict_document jsonb NOT NULL,
    unsatisfied_document jsonb NOT NULL,
    policy_snapshot_document jsonb NOT NULL,
    rationale text DEFAULT ''::text NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    locked_snapshot_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    CONSTRAINT contact_plan_versions_positive CHECK ((version > 0))
);


--
-- Name: contact_planning_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_planning_runs (
    contact_planning_run_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_requirement_id character varying(255) NOT NULL,
    contact_requirement_version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    requested_by character varying(255) NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    summary_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_planning_runs_state_check CHECK ((lifecycle_state IN ('running', 'completed', 'partial', 'failed')))
);


--
-- Name: contact_planning_searches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_planning_searches (
    contact_planning_search_id character varying(255) NOT NULL,
    contact_planning_run_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    route_key text NOT NULL,
    route_order integer NOT NULL,
    provider_id character varying(255),
    provider_version integer,
    provider_account_id character varying(255),
    provider_account_version integer,
    provider_account_grant_id character varying(255),
    provider_account_grant_version integer,
    provider_display_name character varying(255),
    outcome character varying(255) NOT NULL,
    opportunity_count integer DEFAULT 0 NOT NULL,
    route_binding_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    readiness_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_planning_searches_counts_check CHECK (((route_order >= 0) AND (opportunity_count >= 0))),
    CONSTRAINT contact_planning_searches_outcome_check CHECK ((outcome IN ('succeeded_with_results', 'succeeded_without_results', 'not_ready', 'excluded_by_requirement', 'failed')))
);


--
-- Name: contact_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_plans (
    contact_plan_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    current_version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    lifecycle_changed_by character varying(255) NOT NULL,
    lifecycle_changed_at timestamp without time zone NOT NULL,
    lifecycle_reason text DEFAULT ''::text NOT NULL,
    approved_version integer,
    approved_at timestamp without time zone,
    approved_by character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    operation_id character varying(255),
    CONSTRAINT contact_plans_approval_shape CHECK ((((approved_version IS NULL) AND (approved_at IS NULL) AND (approved_by IS NULL)) OR ((approved_version IS NOT NULL) AND (approved_at IS NOT NULL) AND (approved_by IS NOT NULL)))),
    CONSTRAINT contact_plans_state_check CHECK ((lifecycle_state IN ('draft', 'pending_approval', 'approved', 'executing', 'partially_reserved', 'reserved', 'failed', 'canceled', 'superseded'))),
    CONSTRAINT contact_plans_versions_positive CHECK (((current_version > 0) AND ((approved_version IS NULL) OR (approved_version > 0))))
);


--
-- Name: contact_provider_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_provider_profiles (
    provider_profile_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    adapter_key character varying(255) NOT NULL,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL
);


--
-- Name: contact_requirement_occurrences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_requirement_occurrences (
    contact_requirement_occurrence_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_requirement_template_id character varying(255) NOT NULL,
    contact_requirement_template_version integer NOT NULL,
    occurrence_at timestamp without time zone NOT NULL,
    generation_state character varying(255) NOT NULL,
    generated_contact_requirement_id character varying(255),
    generated_contact_requirement_version integer,
    error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    materialized_by character varying(255) NOT NULL,
    materialized_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    CONSTRAINT contact_requirement_occurrences_generated_binding_check CHECK ((((generation_state)::text <> 'generated'::text) OR ((generated_contact_requirement_id IS NOT NULL) AND (generated_contact_requirement_version IS NOT NULL)))),
    CONSTRAINT contact_requirement_occurrences_state_check CHECK ((generation_state IN ('materializing', 'generated', 'failed'))),
    CONSTRAINT contact_requirement_occurrences_version_positive CHECK (((contact_requirement_template_version > 0) AND ((generated_contact_requirement_version IS NULL) OR (generated_contact_requirement_version > 0))))
);


--
-- Name: contact_requirement_template_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_requirement_template_versions (
    contact_requirement_template_version_id character varying(255) NOT NULL,
    contact_requirement_template_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    spacecraft_id character varying(255),
    schedule_document jsonb NOT NULL,
    requirement_document jsonb NOT NULL,
    catch_up_policy_document jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    name text NOT NULL,
    target_document jsonb NOT NULL,
    CONSTRAINT contact_requirement_template_versions_version_positive CHECK ((version > 0))
);


--
-- Name: contact_requirement_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_requirement_templates (
    contact_requirement_template_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    current_version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    lifecycle_changed_by character varying(255) NOT NULL,
    lifecycle_changed_at timestamp without time zone NOT NULL,
    lifecycle_reason text DEFAULT ''::text NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_requirement_templates_current_version_positive CHECK ((current_version > 0)),
    CONSTRAINT contact_requirement_templates_lifecycle_state_check CHECK ((lifecycle_state IN ('active', 'paused', 'closed')))
);


--
-- Name: contact_requirement_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_requirement_versions (
    contact_requirement_version_id character varying(255) NOT NULL,
    contact_requirement_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    service_direction character varying(255) NOT NULL,
    contact_intent character varying(255) NOT NULL,
    earliest_start timestamp without time zone NOT NULL,
    latest_end timestamp without time zone NOT NULL,
    success_measure character varying(255) NOT NULL,
    minimum_duration_seconds integer,
    preferred_duration_seconds integer,
    minimum_data_volume_bytes bigint,
    contact_count integer DEFAULT 1 NOT NULL,
    minimum_separation_seconds integer DEFAULT 0 NOT NULL,
    priority character varying(255) DEFAULT 'routine'::character varying NOT NULL,
    provider_constraints_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    station_constraints_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    policy_constraints_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    approval_policy_document jsonb DEFAULT '{"mode": "manual"}'::jsonb NOT NULL,
    rationale text DEFAULT ''::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    max_gap_seconds integer,
    CONSTRAINT contact_requirement_versions_direction_check CHECK ((service_direction IN ('downlink', 'uplink', 'bidirectional', 'tracking'))),
    CONSTRAINT contact_requirement_versions_duration_order CHECK (((preferred_duration_seconds IS NULL) OR (minimum_duration_seconds IS NULL) OR (preferred_duration_seconds >= minimum_duration_seconds))),
    CONSTRAINT contact_requirement_versions_positive_values CHECK (((version > 0) AND (contact_count > 0) AND (minimum_separation_seconds >= 0) AND ((minimum_duration_seconds IS NULL) OR (minimum_duration_seconds > 0)) AND ((preferred_duration_seconds IS NULL) OR (preferred_duration_seconds > 0)) AND ((minimum_data_volume_bytes IS NULL) OR (minimum_data_volume_bytes > 0)))),
    CONSTRAINT contact_requirement_versions_priority_check CHECK ((priority IN ('routine', 'high', 'critical'))),
    CONSTRAINT contact_requirement_versions_success_measure_check CHECK (((success_measure IN ('any_contact', 'minimum_duration', 'minimum_data_volume', 'contact_count')) AND (((success_measure)::text <> 'minimum_duration'::text) OR (minimum_duration_seconds IS NOT NULL)) AND (((success_measure)::text <> 'minimum_data_volume'::text) OR (minimum_data_volume_bytes IS NOT NULL)))),
    CONSTRAINT contact_requirement_versions_time_range CHECK ((earliest_start < latest_end))
);


--
-- Name: contact_requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_requirements (
    contact_requirement_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    current_version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    lifecycle_changed_by character varying(255) NOT NULL,
    lifecycle_changed_at timestamp without time zone NOT NULL,
    lifecycle_reason text DEFAULT ''::text NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_requirements_current_version_positive CHECK ((current_version > 0)),
    CONSTRAINT contact_requirements_lifecycle_state_check CHECK ((lifecycle_state IN ('active', 'closed', 'canceled')))
);


--
-- Name: contact_schedule_operations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_schedule_operations (
    operation_id uuid NOT NULL,
    organization_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    input jsonb NOT NULL,
    reservation_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    revision integer NOT NULL,
    result jsonb,
    admin_mode boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT contact_schedule_operation_state CHECK (((status IN ('accepted', 'unconfirmed', 'completed', 'rejected')) AND (revision > 0) AND (action IN ('reserve', 'cancel'))))
);


--
-- Name: contact_transport_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_transport_profiles (
    transport_profile_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    target_scope character varying(255) NOT NULL,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL
);


--
-- Name: dashboard_deployments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_deployments (
    dashboard_deployment_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    dashboard_version integer NOT NULL,
    environment character varying(255) NOT NULL,
    artifact_digest character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    created_by character varying(255),
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_investigation_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_investigation_presets (
    dashboard_investigation_preset_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255),
    schema character varying(255) NOT NULL,
    preset_kind character varying(255) NOT NULL,
    runtime_query jsonb DEFAULT '{}'::jsonb NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    primary_data_view character varying(255),
    compare_data_view character varying(255),
    affected_placement_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    created_by character varying(255),
    updated_by character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_library_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_library_items (
    dashboard_library_item_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    latest_version integer DEFAULT 1 NOT NULL,
    created_by character varying(255),
    updated_by character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    retired_at timestamp without time zone,
    retired_by character varying(255)
);


--
-- Name: dashboard_library_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_library_versions (
    dashboard_library_version_id character varying(255) NOT NULL,
    dashboard_library_item_id character varying(255) NOT NULL,
    version integer NOT NULL,
    widget_definition jsonb NOT NULL,
    compatibility jsonb DEFAULT '{}'::jsonb NOT NULL,
    change_summary text,
    created_by character varying(255),
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_lifecycle_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_lifecycle_events (
    dashboard_lifecycle_event_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    event_type character varying(255) NOT NULL,
    dashboard_version integer,
    previous_lifecycle_state character varying(255),
    current_lifecycle_state character varying(255),
    previous_published_version integer,
    current_published_version integer,
    actor_id character varying(255),
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_playlists (
    dashboard_playlist_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    dashboard_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    dwell_seconds integer DEFAULT 30 NOT NULL,
    wallboard_mode boolean DEFAULT false NOT NULL,
    created_by character varying(255),
    updated_by character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_runtime_invalidation_decision_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_runtime_invalidation_decision_events (
    dashboard_runtime_invalidation_decision_event_id character varying(255) NOT NULL,
    invalidation_event_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    boundary character varying(255) NOT NULL,
    domain_fact character varying(255),
    decision_status character varying(255) NOT NULL,
    matches boolean,
    dashboard_matches boolean,
    context_matches boolean,
    context_reason character varying(255),
    refresh_allowed boolean,
    refresh_reason character varying(255),
    affected_placement_count integer,
    affected_placement_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    affected_widget_type_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    affected_impact_reasons character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    invalidated_artifacts integer DEFAULT 0 NOT NULL,
    invalidation_occurred_at timestamp without time zone,
    decision_observed_at timestamp without time zone NOT NULL,
    filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    measurements jsonb DEFAULT '{}'::jsonb NOT NULL,
    decision jsonb DEFAULT '{}'::jsonb NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_shares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_shares (
    dashboard_share_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    created_by character varying(255),
    access_policy character varying(255) DEFAULT 'mission_member'::character varying NOT NULL,
    data_visibility character varying(255) DEFAULT 'authorized_runtime_data'::character varying NOT NULL,
    runtime_context jsonb DEFAULT '{}'::jsonb NOT NULL,
    expires_at timestamp without time zone,
    revoked_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    revoked_by character varying(255)
);


--
-- Name: dashboard_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_snapshots (
    dashboard_snapshot_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    dashboard_version integer NOT NULL,
    created_by character varying(255),
    runtime_context jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_semantics character varying(255) NOT NULL,
    data_visibility character varying(255) DEFAULT 'authorized_runtime_data'::character varying NOT NULL,
    document jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    deleted_at timestamp without time zone,
    deleted_by character varying(255)
);


--
-- Name: dashboard_user_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_user_preferences (
    dashboard_user_preference_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    starred boolean DEFAULT false NOT NULL,
    last_viewed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dashboard_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dashboard_versions (
    dashboard_version_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    dashboard_id character varying(255) NOT NULL,
    version integer NOT NULL,
    document jsonb NOT NULL,
    snapshot_kind character varying(255) NOT NULL,
    parent_version integer,
    based_on_version integer,
    schema_version integer DEFAULT 1 NOT NULL,
    change_summary text,
    created_by character varying(255),
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_binding_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_binding_events (
    data_binding_event_id character varying(255) NOT NULL,
    binding_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255),
    event_type character varying(255) NOT NULL,
    previous_status character varying(255),
    current_status character varying(255) NOT NULL,
    previous_binding_version integer,
    current_binding_version integer NOT NULL,
    previous_logical_source character varying(255),
    current_logical_source character varying(255) NOT NULL,
    previous_realm character varying(255),
    current_realm character varying(255) NOT NULL,
    previous_data_source_id character varying(255),
    current_data_source_id character varying(255) NOT NULL,
    previous_dataset character varying(255),
    current_dataset character varying(255),
    previous_priority integer,
    current_priority integer NOT NULL,
    previous_active_from timestamp without time zone,
    current_active_from timestamp without time zone,
    previous_active_to timestamp without time zone,
    current_active_to timestamp without time zone,
    actor_id character varying(255),
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_bindings (
    binding_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255),
    realm character varying(255) NOT NULL,
    logical_source character varying(255) NOT NULL,
    data_source_id character varying(255) NOT NULL,
    dataset character varying(255),
    priority integer DEFAULT 0 NOT NULL,
    active_from timestamp without time zone,
    active_to timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    binding_version integer DEFAULT 1 NOT NULL,
    current_event_id character varying(255),
    disabled_at timestamp without time zone,
    superseded_at timestamp without time zone
);


--
-- Name: data_source_credential_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_credential_events (
    source_credential_event_id character varying(255) NOT NULL,
    credentials_ref character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255),
    data_source_id character varying(255),
    event_type character varying(255) NOT NULL,
    previous_status character varying(255),
    current_status character varying(255) NOT NULL,
    previous_credential_version integer,
    current_credential_version integer NOT NULL,
    actor_id character varying(255),
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_credential_references; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_credential_references (
    credentials_ref character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255),
    data_source_id character varying(255),
    owner character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    provider character varying(255),
    status character varying(255) NOT NULL,
    credential_version integer DEFAULT 1 NOT NULL,
    current_event_id character varying(255),
    last_rotated_at timestamp without time zone,
    disabled_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_definition_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_definition_events (
    data_source_event_id character varying(255) NOT NULL,
    data_source_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255),
    event_type character varying(255) NOT NULL,
    previous_owner character varying(255),
    current_owner character varying(255) NOT NULL,
    previous_kind character varying(255),
    current_kind character varying(255) NOT NULL,
    previous_adapter character varying(255),
    current_adapter character varying(255),
    previous_isolation_level character varying(255),
    current_isolation_level character varying(255) NOT NULL,
    previous_credentials_ref character varying(255),
    current_credentials_ref character varying(255),
    previous_capabilities jsonb,
    current_capabilities jsonb DEFAULT '{}'::jsonb NOT NULL,
    previous_metadata jsonb,
    current_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    actor_id character varying(255),
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    previous_status character varying(255),
    current_status character varying(255) DEFAULT 'active'::character varying NOT NULL
);


--
-- Name: data_source_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_definitions (
    data_source_id character varying(255) NOT NULL,
    owner character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    adapter character varying(255),
    organization_id character varying(255),
    mission_id character varying(255),
    isolation_level character varying(255) NOT NULL,
    capabilities jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    credentials_ref character varying(255),
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    current_event_id character varying(255),
    disabled_at timestamp without time zone
);


--
-- Name: data_source_health_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_health_events (
    source_health_event_id character varying(255) NOT NULL,
    source_health_key character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    logical_source character varying(255) NOT NULL,
    data_source_id character varying(255) NOT NULL,
    source_binding_id character varying(255),
    realm character varying(255),
    replay_run_id character varying(255),
    dataset character varying(255),
    event_type character varying(255) NOT NULL,
    source_health character varying(255) NOT NULL,
    previous_source_health character varying(255),
    reason character varying(255),
    observed_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_health_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_health_statuses (
    source_health_key character varying(255) NOT NULL,
    source_health_event_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    logical_source character varying(255) NOT NULL,
    data_source_id character varying(255) NOT NULL,
    source_binding_id character varying(255),
    realm character varying(255),
    replay_run_id character varying(255),
    dataset character varying(255),
    event_type character varying(255) NOT NULL,
    source_health character varying(255) NOT NULL,
    previous_source_health character varying(255),
    reason character varying(255),
    observed_at timestamp without time zone NOT NULL,
    last_seen_at timestamp without time zone NOT NULL,
    transition_count integer DEFAULT 1 NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_watermark_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_watermark_events (
    source_watermark_event_id character varying(255) NOT NULL,
    source_watermark_key character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    logical_source character varying(255) NOT NULL,
    data_source_id character varying(255) NOT NULL,
    source_binding_id character varying(255),
    realm character varying(255),
    replay_run_id character varying(255),
    dataset character varying(255),
    event_type character varying(255) NOT NULL,
    complete_through timestamp without time zone,
    previous_complete_through timestamp without time zone,
    latest_receipt_time timestamp without time zone,
    previous_latest_receipt_time timestamp without time zone,
    retention_starts_at timestamp without time zone,
    previous_retention_starts_at timestamp without time zone,
    sample_count integer,
    confidence character varying(255) NOT NULL,
    reason character varying(255),
    observed_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: data_source_watermark_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_source_watermark_statuses (
    source_watermark_key character varying(255) NOT NULL,
    source_watermark_event_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    logical_source character varying(255) NOT NULL,
    data_source_id character varying(255) NOT NULL,
    source_binding_id character varying(255),
    realm character varying(255),
    replay_run_id character varying(255),
    dataset character varying(255),
    event_type character varying(255) NOT NULL,
    complete_through timestamp without time zone,
    previous_complete_through timestamp without time zone,
    latest_receipt_time timestamp without time zone,
    previous_latest_receipt_time timestamp without time zone,
    retention_starts_at timestamp without time zone,
    previous_retention_starts_at timestamp without time zone,
    sample_count integer,
    confidence character varying(255) NOT NULL,
    reason character varying(255),
    observed_at timestamp without time zone NOT NULL,
    last_seen_at timestamp without time zone NOT NULL,
    transition_count integer DEFAULT 1 NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: derived_telemetry_evaluation_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.derived_telemetry_evaluation_runs (
    derived_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    evaluated_sample_count integer DEFAULT 0 NOT NULL,
    emitted_sample_count integer DEFAULT 0 NOT NULL,
    definition_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: derived_telemetry_latest_value_rebuild_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.derived_telemetry_latest_value_rebuild_runs (
    rebuild_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    rebuilt_value_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: derived_telemetry_latest_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.derived_telemetry_latest_values (
    id bigint NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_scope_id character varying(255) DEFAULT ''::character varying NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    derived_sample_id character varying(255) NOT NULL,
    derived_definition_id character varying(255) NOT NULL,
    derived_definition_version integer NOT NULL,
    trigger_sample_id character varying(255) NOT NULL,
    value jsonb NOT NULL,
    quality_state character varying(255) NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: derived_telemetry_latest_values_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.derived_telemetry_latest_values_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: derived_telemetry_latest_values_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.derived_telemetry_latest_values_id_seq OWNED BY public.derived_telemetry_latest_values.id;


--
-- Name: derived_telemetry_samples; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.derived_telemetry_samples (
    derived_sample_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    derived_definition_id character varying(255) NOT NULL,
    derived_definition_version integer NOT NULL,
    trigger_sample_id character varying(255) NOT NULL,
    value jsonb NOT NULL,
    quality_state character varying(255) NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: downlink_diagnostics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.downlink_diagnostics (
    diagnostic_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    observation_key character varying(255) NOT NULL,
    path_id character varying(255) NOT NULL,
    selected_path_id character varying(255) NOT NULL,
    observation_id character varying(255) NOT NULL,
    competing_observation_id character varying(255),
    diagnostic_kind character varying(255) NOT NULL,
    recorded_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: downlink_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.downlink_observations (
    observation_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    path_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    observation_key character varying(255) NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score integer DEFAULT 0 NOT NULL,
    observed_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: federated_application_action_idempotencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.federated_application_action_idempotencies (
    id bigint NOT NULL,
    organization_id character varying(255) NOT NULL,
    actor_kind character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    scope_kind character varying(255) NOT NULL,
    scope_id character varying(255) NOT NULL,
    application_key character varying(255) NOT NULL,
    application_version integer NOT NULL,
    surface_id character varying(255) NOT NULL,
    surface_version integer NOT NULL,
    operation character varying(255) NOT NULL,
    operation_version integer NOT NULL,
    generation_id character varying(255) NOT NULL,
    release_id character varying(255) NOT NULL,
    idempotency_key_digest character varying(255) NOT NULL,
    request_digest character varying(255) NOT NULL,
    state character varying(255) NOT NULL,
    claim_token character varying(255),
    lease_expires_at timestamp without time zone,
    response_status integer,
    response_content_type character varying(255),
    response_body bytea,
    completed_at timestamp without time zone,
    retention_expires_at timestamp without time zone NOT NULL,
    retention_reference character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT faaid_digest_format_check CHECK ((((idempotency_key_digest)::text ~ '^hmac-sha256:[0-9a-f]{64}$'::text) AND ((request_digest)::text ~ '^hmac-sha256:[0-9a-f]{64}$'::text))),
    CONSTRAINT faaid_identity_bounds_check CHECK (octet_length(organization_id) BETWEEN 1 AND 255 AND
        octet_length(actor_kind) BETWEEN 1 AND 32 AND
        octet_length(actor_id) BETWEEN 1 AND 255 AND
        octet_length(mission_id) BETWEEN 1 AND 255 AND
        octet_length(scope_kind) BETWEEN 1 AND 32 AND
        octet_length(scope_id) BETWEEN 1 AND 255 AND
        octet_length(application_key) BETWEEN 1 AND 255 AND
        octet_length(surface_id) BETWEEN 1 AND 255 AND
        octet_length(operation) BETWEEN 1 AND 255 AND
        octet_length(generation_id) BETWEEN 1 AND 255 AND
        octet_length(release_id) BETWEEN 1 AND 255 AND
        octet_length(retention_reference) BETWEEN 1 AND 512),
    CONSTRAINT faaid_response_state_check CHECK (((((state)::text = 'in_progress'::text) AND (claim_token IS NOT NULL) AND (lease_expires_at IS NOT NULL) AND (response_status IS NULL) AND (response_content_type IS NULL) AND (response_body IS NULL) AND (completed_at IS NULL)) OR ((state IN ('completed', 'failed', 'indeterminate')) AND (claim_token IS NULL) AND (lease_expires_at IS NULL) AND ((response_status >= 100) AND (response_status <= 599)) AND ((response_content_type)::text = 'application/json; charset=utf-8'::text) AND (response_body IS NOT NULL) AND ((octet_length(response_body) >= 1) AND (octet_length(response_body) <=
CASE
    WHEN ((application_key)::text = 'derived_telemetry'::text) THEN 65536
    ELSE 16384
END)) AND (completed_at IS NOT NULL)))),
    CONSTRAINT faaid_state_check CHECK ((state IN ('in_progress', 'completed', 'failed', 'indeterminate'))),
    CONSTRAINT faaid_version_bounds_check CHECK (((application_version > 0) AND (surface_version > 0) AND (operation_version > 0)))
);


--
-- Name: federated_application_action_idempotencies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.federated_application_action_idempotencies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: federated_application_action_idempotencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.federated_application_action_idempotencies_id_seq OWNED BY public.federated_application_action_idempotencies.id;


--
-- Name: fleet_automation_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_automation_actions (
    fleet_automation_action_id character varying(255) NOT NULL,
    idempotency_key character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    automation_grant_id character varying(255) NOT NULL,
    automation_grant_content_sha256 character varying(255) NOT NULL,
    service_identity_id character varying(255) NOT NULL,
    fleet_planning_run_id character varying(255) NOT NULL,
    contact_plan_id character varying(255),
    contact_plan_version integer,
    action character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    attempt_count integer DEFAULT 1 NOT NULL,
    evidence_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT fleet_automation_actions_action_check CHECK ((action IN ('plan', 'repair', 'submit', 'approve', 'execute'))),
    CONSTRAINT fleet_automation_actions_attempt_count_check CHECK ((attempt_count > 0)),
    CONSTRAINT fleet_automation_actions_plan_binding_check CHECK (((contact_plan_id IS NULL) = (contact_plan_version IS NULL))),
    CONSTRAINT fleet_automation_actions_state_check CHECK ((lifecycle_state IN ('running', 'succeeded', 'failed', 'skipped')))
);


--
-- Name: fleet_planning_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_planning_decisions (
    fleet_planning_decision_id character varying(255) NOT NULL,
    fleet_planning_run_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_opportunity_snapshot_id character varying(255) NOT NULL,
    disposition character varying(255) NOT NULL,
    score bigint NOT NULL,
    rank integer,
    hard_constraint_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    score_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    explanation_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT fleet_planning_decisions_disposition_check CHECK ((disposition IN ('selected', 'displaced', 'ineligible', 'locked'))),
    CONSTRAINT fleet_planning_decisions_rank_positive CHECK (((rank IS NULL) OR (rank > 0)))
);


--
-- Name: fleet_planning_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_planning_policies (
    fleet_planning_policy_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    current_version integer NOT NULL,
    active_version integer,
    lifecycle_state character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    lifecycle_changed_by character varying(255) NOT NULL,
    lifecycle_changed_at timestamp without time zone NOT NULL,
    lifecycle_reason text DEFAULT ''::text NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT fleet_planning_policies_lifecycle_state_check CHECK ((lifecycle_state IN ('draft', 'active', 'retired'))),
    CONSTRAINT fleet_planning_policies_versions_positive CHECK (((current_version > 0) AND ((active_version IS NULL) OR (active_version > 0))))
);


--
-- Name: fleet_planning_policy_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_planning_policy_approvals (
    fleet_planning_policy_approval_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    fleet_planning_policy_id character varying(255) NOT NULL,
    fleet_planning_policy_version integer NOT NULL,
    decision character varying(255) NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    reason text NOT NULL,
    actor_user_id character varying(255) NOT NULL,
    actor_document jsonb NOT NULL,
    decided_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    policy_document jsonb,
    CONSTRAINT fleet_planning_policy_approvals_decision_check CHECK ((decision IN ('approved', 'rejected'))),
    CONSTRAINT fleet_planning_policy_approvals_version_positive CHECK ((fleet_planning_policy_version > 0))
);


--
-- Name: fleet_planning_policy_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_planning_policy_versions (
    fleet_planning_policy_version_id character varying(255) NOT NULL,
    fleet_planning_policy_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    horizon_document jsonb NOT NULL,
    scoring_document jsonb NOT NULL,
    resource_policy_document jsonb NOT NULL,
    budget_quota_document jsonb NOT NULL,
    redundancy_document jsonb NOT NULL,
    automation_repair_document jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    reason text,
    CONSTRAINT fleet_planning_policy_versions_version_positive CHECK ((version > 0))
);


--
-- Name: fleet_planning_run_requirement_refs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_planning_run_requirement_refs (
    fleet_planning_run_requirement_ref_id character varying(255) NOT NULL,
    fleet_planning_run_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    contact_requirement_id character varying(255) NOT NULL,
    contact_requirement_version integer NOT NULL,
    contact_planning_run_id character varying(255),
    input_state character varying(255) NOT NULL,
    result_state character varying(255) NOT NULL,
    explanation_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    input_content_sha256 character varying(255) NOT NULL,
    CONSTRAINT fleet_planning_run_requirement_refs_input_state_check CHECK ((input_state IN ('pending', 'searching', 'searched', 'failed'))),
    CONSTRAINT fleet_planning_run_requirement_refs_result_state_check CHECK ((result_state IN ('pending', 'satisfied', 'partial', 'unsatisfied', 'failed'))),
    CONSTRAINT fleet_planning_run_requirement_refs_version_positive CHECK ((contact_requirement_version > 0))
);


--
-- Name: fleet_planning_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fleet_planning_runs (
    fleet_planning_run_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    phase character varying(255) NOT NULL,
    trigger_kind character varying(255) NOT NULL,
    fleet_planning_policy_id character varying(255) NOT NULL,
    fleet_planning_policy_version integer NOT NULL,
    algorithm_key character varying(255) NOT NULL,
    algorithm_version integer NOT NULL,
    horizon_start timestamp without time zone NOT NULL,
    horizon_end timestamp without time zone NOT NULL,
    source_fleet_planning_run_id character varying(255),
    source_contact_plan_id character varying(255),
    source_contact_plan_version integer,
    candidate_contact_plan_id character varying(255),
    candidate_contact_plan_version integer,
    input_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    progress_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_summary_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    failure_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    trigger_actor_document jsonb NOT NULL,
    triggered_by character varying(255) NOT NULL,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    operation_id character varying(255),
    CONSTRAINT fleet_planning_runs_candidate_binding_check CHECK (((candidate_contact_plan_id IS NULL) = (candidate_contact_plan_version IS NULL))),
    CONSTRAINT fleet_planning_runs_horizon_check CHECK ((horizon_start < horizon_end)),
    CONSTRAINT fleet_planning_runs_phase_check CHECK ((phase IN ('queued', 'materializing', 'searching', 'optimizing', 'materializing_plan', 'finished'))),
    CONSTRAINT fleet_planning_runs_source_binding_check CHECK ((((trigger_kind)::text <> 'repair'::text) OR ((source_fleet_planning_run_id IS NOT NULL) AND (source_contact_plan_id IS NOT NULL) AND (source_contact_plan_version IS NOT NULL)))),
    CONSTRAINT fleet_planning_runs_state_check CHECK ((lifecycle_state IN ('queued', 'running', 'completed', 'partial', 'failed', 'canceled'))),
    CONSTRAINT fleet_planning_runs_trigger_check CHECK ((trigger_kind IN ('manual', 'scheduled', 'repair'))),
    CONSTRAINT fleet_planning_runs_versions_positive CHECK (((fleet_planning_policy_version > 0) AND (algorithm_version > 0) AND ((source_contact_plan_version IS NULL) OR (source_contact_plan_version > 0)) AND ((candidate_contact_plan_version IS NULL) OR (candidate_contact_plan_version > 0))))
);


--
-- Name: frontend_release_activation_controls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_activation_controls (
    control_id integer NOT NULL,
    cutover_epoch bigint DEFAULT 0 NOT NULL,
    cutover_at timestamp without time zone,
    legacy_catalog_publication_id character varying(255),
    CONSTRAINT frontend_release_activation_controls_cutover_check CHECK ((((cutover_epoch = 0) AND (cutover_at IS NULL) AND (legacy_catalog_publication_id IS NULL)) OR ((cutover_epoch > 0) AND (cutover_at IS NOT NULL)))),
    CONSTRAINT frontend_release_activation_controls_singleton_check CHECK ((control_id = 1))
);


--
-- Name: frontend_release_activation_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_activation_requests (
    request_id character varying(255) NOT NULL,
    idempotency_key_digest character varying(255) NOT NULL,
    document_digest character varying(255) NOT NULL,
    outcome character varying(255) NOT NULL,
    response_status integer NOT NULL,
    response_body bytea NOT NULL,
    catalog_publication_id character varying(255),
    generation_id character varying(255),
    publisher_identity character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frar_document_digest_check CHECK (((document_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frar_idempotency_key_digest_check CHECK (((idempotency_key_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frar_outcome_check CHECK ((outcome IN ('initial', 'legacy_successor', 'promotion', 'rollback', 'rejected'))),
    CONSTRAINT frar_outcome_response_check CHECK (((((outcome)::text = 'rejected'::text) AND (response_status = 422) AND (catalog_publication_id IS NULL) AND (generation_id IS NULL)) OR ((outcome IN ('initial', 'legacy_successor', 'promotion', 'rollback')) AND (response_status = 201) AND (catalog_publication_id IS NOT NULL) AND (generation_id IS NOT NULL)))),
    CONSTRAINT frar_publisher_identity_check CHECK (((publisher_identity IS NULL) OR ((octet_length((publisher_identity)::text) > 0) AND (octet_length((publisher_identity)::text) <= 128)))),
    CONSTRAINT frar_response_body_check CHECK (((octet_length(response_body) > 0) AND (octet_length(response_body) <= 16384))),
    CONSTRAINT frar_response_status_check CHECK ((response_status = ANY (ARRAY[201, 422])))
);


--
-- Name: frontend_release_artifacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_artifacts (
    artifact_id character varying(255) NOT NULL,
    release_publication_id character varying(255) NOT NULL,
    release_id character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    sha256 character varying(255) NOT NULL,
    size bigint NOT NULL,
    media_type character varying(255) NOT NULL,
    object_key character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frontend_release_artifacts_object_key_check CHECK (((object_key)::text = ('sha256:'::text || (sha256)::text))),
    CONSTRAINT frontend_release_artifacts_sha256_check CHECK (((sha256)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_artifacts_size_check CHECK (((size >= 0) AND (size <= 100000000)))
);


--
-- Name: frontend_release_catalog_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_catalog_bindings (
    generation_id character varying(255) NOT NULL,
    application_id character varying(255) NOT NULL,
    application_version integer NOT NULL,
    package_id character varying(255) NOT NULL,
    package_version integer NOT NULL,
    surface_id character varying(255) NOT NULL,
    surface_version integer NOT NULL,
    current_publication_id character varying(255) NOT NULL,
    current_release_id character varying(255) NOT NULL,
    previous_publication_id character varying(255),
    previous_release_id character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frcb_current_pair_check CHECK (((current_publication_id IS NOT NULL) AND (current_release_id IS NOT NULL))),
    CONSTRAINT frcb_identity_version_check CHECK (((application_version > 0) AND (package_version > 0) AND (surface_version > 0))),
    CONSTRAINT frcb_previous_pair_check CHECK ((((previous_publication_id IS NULL) AND (previous_release_id IS NULL)) OR ((previous_publication_id IS NOT NULL) AND (previous_release_id IS NOT NULL))))
);


--
-- Name: frontend_release_catalog_generations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_catalog_generations (
    generation_id character varying(255) NOT NULL,
    catalog_publication_id character varying(255) NOT NULL,
    sequence bigint NOT NULL,
    identity_count integer NOT NULL,
    predecessor_kind character varying(255) NOT NULL,
    predecessor_catalog_publication_id character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frcg_identity_count_check CHECK ((identity_count > 0)),
    CONSTRAINT frcg_predecessor_check CHECK (((((predecessor_kind)::text = 'none'::text) AND (predecessor_catalog_publication_id IS NULL)) OR ((predecessor_kind IN ('legacy', 'generation')) AND (predecessor_catalog_publication_id IS NOT NULL)))),
    CONSTRAINT frcg_sequence_check CHECK ((sequence > 0))
);


--
-- Name: frontend_release_catalog_publications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_catalog_publications (
    publication_id character varying(255) NOT NULL,
    sequence bigint NOT NULL,
    catalog_digest character varying(255) NOT NULL,
    signed_document_digest character varying(255) NOT NULL,
    signed_document_bytes bytea NOT NULL,
    payload_bytes bytea NOT NULL,
    signing_key_id character varying(255) NOT NULL,
    signing_role character varying(255) NOT NULL,
    published_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    acceptance_state character varying(255) DEFAULT 'accepted'::character varying NOT NULL,
    accepted_state jsonb NOT NULL,
    release_references jsonb NOT NULL,
    accepted_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    transition character varying(255),
    identity_count integer,
    snapshot_digest character varying(255),
    CONSTRAINT frcp_acceptance_state_check CHECK (((acceptance_state)::text = 'accepted'::text)),
    CONSTRAINT frcp_catalog_digest_check CHECK (((catalog_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frcp_sequence_check CHECK ((sequence > 0)),
    CONSTRAINT frcp_signed_document_digest_check CHECK (((signed_document_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frcp_signing_role_check CHECK (((signing_role)::text = 'promotion'::text)),
    CONSTRAINT frcp_v2_transition_fields_check CHECK ((((transition IS NULL) AND (identity_count IS NULL) AND (snapshot_digest IS NULL)) OR ((transition IS NOT NULL) AND (identity_count IS NOT NULL) AND (snapshot_digest IS NOT NULL) AND (transition IN ('initial', 'legacy_successor', 'promotion', 'rollback')) AND (identity_count > 0) AND ((snapshot_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)))),
    CONSTRAINT frcp_window_check CHECK ((expires_at > published_at))
);


--
-- Name: frontend_release_object_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_object_chunks (
    sha256 character varying(255) NOT NULL,
    chunk_index integer NOT NULL,
    bytes bytea NOT NULL,
    size integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frontend_release_object_chunks_index_check CHECK ((chunk_index >= 0)),
    CONSTRAINT frontend_release_object_chunks_size_check CHECK (((size > 0) AND (size <= 1048576) AND (octet_length(bytes) = size)))
);


--
-- Name: frontend_release_objects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_objects (
    sha256 character varying(255) NOT NULL,
    bytes bytea,
    size bigint NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frontend_release_objects_octet_length_check CHECK (((bytes IS NULL) OR ((octet_length(bytes) = size) AND (octet_length(bytes) <= 100000000)))),
    CONSTRAINT frontend_release_objects_sha256_check CHECK (((sha256)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_objects_size_check CHECK (((size >= 0) AND (size <= 100000000)))
);


--
-- Name: frontend_release_publications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_publications (
    publication_id character varying(255) NOT NULL,
    release_id character varying(255) NOT NULL,
    application_id character varying(255) NOT NULL,
    application_version integer NOT NULL,
    package_id character varying(255) NOT NULL,
    package_version integer NOT NULL,
    surface_id character varying(255) NOT NULL,
    surface_version integer NOT NULL,
    remote_name character varying(255) NOT NULL,
    exposed_module character varying(255) NOT NULL,
    artifact_base_url character varying(255) NOT NULL,
    payload_digest character varying(255) NOT NULL,
    signed_document_digest character varying(255) NOT NULL,
    signed_document_bytes bytea NOT NULL,
    payload_bytes bytea NOT NULL,
    signing_key_id character varying(255) NOT NULL,
    signing_role character varying(255) NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    released_at timestamp without time zone NOT NULL,
    artifact_count integer NOT NULL,
    acceptance_state character varying(255) DEFAULT 'accepted'::character varying NOT NULL,
    accepted_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    manifest_path character varying(255) NOT NULL,
    manifest_sha256 character varying(255) NOT NULL,
    manifest_size bigint NOT NULL,
    manifest_media_type character varying(255) NOT NULL,
    CONSTRAINT frontend_release_publications_acceptance_state_check CHECK (((acceptance_state)::text = 'accepted'::text)),
    CONSTRAINT frontend_release_publications_artifact_count_check CHECK ((artifact_count > 0)),
    CONSTRAINT frontend_release_publications_manifest_media_type_check CHECK (((octet_length((manifest_media_type)::text) > 0) AND (octet_length((manifest_media_type)::text) <= 128) AND ((manifest_media_type)::text ~ '^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$'::text))),
    CONSTRAINT frontend_release_publications_manifest_path_check CHECK (((octet_length((manifest_path)::text) > 0) AND (octet_length((manifest_path)::text) <= 256) AND (POSITION((chr(92)) IN (manifest_path)) = 0) AND ((manifest_path)::text !~ '(^/|//|(^|/)\.{1,2}(/|$))'::text))),
    CONSTRAINT frontend_release_publications_manifest_sha256_check CHECK (((manifest_sha256)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_publications_manifest_size_check CHECK (((manifest_size >= 0) AND (manifest_size <= 100000000))),
    CONSTRAINT frontend_release_publications_payload_digest_check CHECK (((payload_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_publications_release_id_check CHECK (((release_id)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_publications_signed_document_digest_check CHECK (((signed_document_digest)::text ~ '^sha256:[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_publications_signing_role_check CHECK (((signing_role)::text = 'release'::text))
);


--
-- Name: frontend_release_staged_object_chunks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_staged_object_chunks (
    sha256 character varying(255) NOT NULL,
    chunk_index integer NOT NULL,
    bytes bytea NOT NULL,
    size integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frontend_release_staged_object_chunks_index_check CHECK ((chunk_index >= 0)),
    CONSTRAINT frontend_release_staged_object_chunks_size_check CHECK (((size > 0) AND (size <= 1048576) AND (octet_length(bytes) = size)))
);


--
-- Name: frontend_release_staged_objects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.frontend_release_staged_objects (
    sha256 character varying(255) NOT NULL,
    size bigint NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT frontend_release_staged_objects_sha256_check CHECK (((sha256)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT frontend_release_staged_objects_size_check CHECK (((size >= 0) AND (size <= 100000000)))
);


--
-- Name: governed_binding_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_binding_rules (
    id bigint NOT NULL,
    binding_set_row_id bigint NOT NULL,
    binding_rule_id character varying(255) NOT NULL,
    handler_key character varying(255) NOT NULL,
    packet_kind character varying(255),
    apid integer,
    priority integer NOT NULL,
    fanout_mode character varying(255) NOT NULL,
    handler_configuration_type character varying(255),
    handler_configuration_ref jsonb,
    inserted_at timestamp without time zone NOT NULL,
    source_endpoint_ref character varying(255),
    selector_scope jsonb DEFAULT '{}'::jsonb NOT NULL,
    selector_match jsonb DEFAULT '{}'::jsonb NOT NULL,
    capability_config_type character varying(255) DEFAULT 'none'::character varying NOT NULL,
    capability_config_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    capability_instance_id character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: governed_binding_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_binding_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_binding_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_binding_rules_id_seq OWNED BY public.governed_binding_rules.id;


--
-- Name: governed_binding_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_binding_sets (
    id bigint NOT NULL,
    mission_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    version integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: governed_binding_sets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_binding_sets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_binding_sets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_binding_sets_id_seq OWNED BY public.governed_binding_sets.id;


--
-- Name: governed_capability_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_capability_instances (
    id bigint NOT NULL,
    binding_set_row_id bigint NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    target_scope character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL,
    capability_config_type character varying(255) DEFAULT 'none'::character varying NOT NULL,
    capability_config_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: governed_capability_instances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_capability_instances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_capability_instances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_capability_instances_id_seq OWNED BY public.governed_capability_instances.id;


--
-- Name: governed_derived_telemetry_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_derived_telemetry_definitions (
    id bigint NOT NULL,
    mission_id character varying(255) NOT NULL,
    derived_definition_id character varying(255) NOT NULL,
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    expression text NOT NULL,
    version integer NOT NULL,
    source_point_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    retired_at timestamp without time zone,
    retired_by character varying(255)
);


--
-- Name: governed_derived_telemetry_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_derived_telemetry_definitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_derived_telemetry_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_derived_telemetry_definitions_id_seq OWNED BY public.governed_derived_telemetry_definitions.id;


--
-- Name: governed_limit_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_limit_definitions (
    id bigint NOT NULL,
    mission_id character varying(255) NOT NULL,
    limit_definition_id character varying(255) NOT NULL,
    point_id character varying(255) NOT NULL,
    version integer NOT NULL,
    limit_set_name character varying(255) NOT NULL,
    thresholds jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: governed_limit_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_limit_definitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_limit_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_limit_definitions_id_seq OWNED BY public.governed_limit_definitions.id;


--
-- Name: governed_packet_definition_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_packet_definition_fields (
    id bigint NOT NULL,
    packet_definition_row_id bigint NOT NULL,
    field_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    offset_bits integer NOT NULL,
    size_bits integer NOT NULL,
    data_type character varying(255) NOT NULL,
    byte_order character varying(255) NOT NULL,
    engineering_unit character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    parameter_id text,
    qualified_name text
);


--
-- Name: governed_packet_definition_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_packet_definition_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_packet_definition_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_packet_definition_fields_id_seq OWNED BY public.governed_packet_definition_fields.id;


--
-- Name: governed_packet_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.governed_packet_definitions (
    id bigint NOT NULL,
    mission_id character varying(255) NOT NULL,
    packet_definition_id character varying(255) NOT NULL,
    packet_name character varying(255) NOT NULL,
    apid integer NOT NULL,
    version integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: governed_packet_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.governed_packet_definitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: governed_packet_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.governed_packet_definitions_id_seq OWNED BY public.governed_packet_definitions.id;


--
-- Name: ground_station_availability_windows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ground_station_availability_windows (
    window_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    ground_station_id character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    starts_at timestamp without time zone NOT NULL,
    ends_at timestamp without time zone,
    eta timestamp without time zone,
    source character varying(255) NOT NULL,
    reported_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    provider_ref character varying(255),
    reason text,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    cleared_at timestamp without time zone,
    cleared_by jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: ingress_archive_evidence_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingress_archive_evidence_entries (
    evidence_id character varying(255) NOT NULL,
    segment_id character varying(255) NOT NULL,
    object_key character varying(255) NOT NULL,
    archive_backend character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    organization_id character varying(255),
    source_endpoint_ref character varying(255),
    spacecraft_id character varying(255),
    protocol_family character varying(255) NOT NULL,
    direction character varying(255) NOT NULL,
    source_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    source_ref character varying(255),
    realized_contact_id character varying(255),
    path_id character varying(255),
    provider_binding_id character varying(255),
    raw_size_bytes integer NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    content_sha256 bytea
);


--
-- Name: ingress_raw_evidence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingress_raw_evidence (
    evidence_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    protocol_family character varying(255) NOT NULL,
    direction character varying(255) NOT NULL,
    raw bytea NOT NULL,
    source_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    source_ref character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    source_endpoint_ref character varying(255),
    organization_id character varying(255)
);


--
-- Name: job_outcome_resolutions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_outcome_resolutions (
    item_id character varying(255) NOT NULL,
    job_id character varying(255) NOT NULL,
    attempt integer NOT NULL,
    mission_id character varying(255) NOT NULL,
    job_type character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    actor jsonb NOT NULL,
    note text,
    resolved_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: limit_definition_lifecycle_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.limit_definition_lifecycle_events (
    limit_definition_lifecycle_event_id character varying(255) NOT NULL,
    definition_activation_key character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    point_id character varying(255) NOT NULL,
    limit_set_name character varying(255) NOT NULL,
    scope_type character varying(255),
    scope_ref character varying(255),
    realm character varying(255),
    event_type character varying(255) NOT NULL,
    limit_definition_id character varying(255) NOT NULL,
    limit_definition_version integer NOT NULL,
    previous_limit_definition_id character varying(255),
    previous_limit_definition_version integer,
    active_from timestamp without time zone NOT NULL,
    active_to timestamp without time zone,
    reason character varying(255),
    observed_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: managed_action_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.managed_action_requests (
    action_request_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    action_kind character varying(255) NOT NULL,
    packet_id character varying(255),
    evidence_id character varying(255),
    request_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: managed_capability_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.managed_capability_records (
    capability_record_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    event_kind character varying(255) NOT NULL,
    packet_id character varying(255),
    evidence_id character varying(255),
    timer_key character varying(255),
    emitted_record_kinds jsonb DEFAULT '{}'::jsonb NOT NULL,
    emitted_record_count integer NOT NULL,
    action_request_count integer NOT NULL,
    state_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    recorded_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: managed_timer_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.managed_timer_events (
    timer_event_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    timer_key character varying(255) NOT NULL,
    event_kind character varying(255) NOT NULL,
    packet_id character varying(255),
    evidence_id character varying(255),
    due_at timestamp without time zone,
    occurred_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: mission_active_binding_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_active_binding_sets (
    mission_id character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    activated_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    generation bigint NOT NULL,
    binding_set_content_sha256 character varying(255),
    activation_request_id character varying(255)
);


--
-- Name: mission_binding_set_activations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_binding_set_activations (
    activation_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    activated_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    generation bigint NOT NULL,
    binding_set_content_sha256 character varying(255),
    activation_request_id character varying(255)
);


--
-- Name: mission_config_change_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_change_sets (
    change_set_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    state character varying(255) NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    base_revision_number integer NOT NULL,
    opened_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    opened_at timestamp without time zone NOT NULL,
    submitted_by jsonb,
    submitted_at timestamp without time zone,
    reason text,
    policy_document jsonb,
    failure_document jsonb,
    applied_revision_number integer,
    closed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: mission_config_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_changes (
    change_id character varying(255) NOT NULL,
    change_set_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    author jsonb NOT NULL,
    author_key character varying(255) NOT NULL,
    staged_at timestamp without time zone NOT NULL,
    summary text NOT NULL,
    source jsonb DEFAULT '{}'::jsonb NOT NULL,
    state character varying(255) NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: mission_config_heads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_heads (
    mission_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    revision_number integer NOT NULL,
    revision_id character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: mission_config_ops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_ops (
    op_id character varying(255) NOT NULL,
    change_id character varying(255) NOT NULL,
    change_set_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    "position" integer NOT NULL,
    kind character varying(255) NOT NULL,
    entity_id character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    base jsonb DEFAULT '{}'::jsonb NOT NULL,
    touched_paths character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL
);


--
-- Name: mission_config_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_reviews (
    review_id character varying(255) NOT NULL,
    change_set_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    decision character varying(255) NOT NULL,
    actor jsonb NOT NULL,
    comment text,
    decided_at timestamp without time zone NOT NULL,
    subject_version integer NOT NULL,
    subject_digest character varying(255) NOT NULL,
    policy_document jsonb NOT NULL,
    separated_from character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    admin_mode boolean NOT NULL,
    CONSTRAINT mission_config_reviews_comment_unless_approved CHECK (((comment IS NOT NULL) OR (decision IN ('approved', 'not_required')))),
    CONSTRAINT mission_config_reviews_decision_check CHECK ((decision IN ('approved', 'sent_back', 'not_required'))),
    CONSTRAINT mission_config_reviews_subject_digest_check CHECK (((subject_digest)::text ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: mission_config_revision_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_revision_entries (
    entry_id character varying(255) NOT NULL,
    revision_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    revision_number integer NOT NULL,
    "position" integer NOT NULL,
    kind character varying(255) NOT NULL,
    entity_id character varying(255) NOT NULL,
    op character varying(255) NOT NULL,
    before jsonb,
    after jsonb,
    paths character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL
);


--
-- Name: mission_config_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_config_revisions (
    revision_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    revision_number integer NOT NULL,
    kind character varying(255) NOT NULL,
    change_set_id character varying(255),
    rolls_back_to integer,
    applied_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    applied_at timestamp without time zone NOT NULL,
    reason text NOT NULL,
    approvals jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    summary text NOT NULL,
    entry_count integer DEFAULT 0 NOT NULL,
    activation_id character varying(255),
    generation bigint,
    content_sha256 character varying(255),
    submitted_by jsonb NOT NULL
);


--
-- Name: mission_event_rebuild_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_event_rebuild_runs (
    rebuild_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    rebuilt_event_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: mission_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_events (
    mission_event_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    occurred_at timestamp without time zone NOT NULL,
    category character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    severity character varying(255),
    status character varying(255),
    title character varying(255) NOT NULL,
    summary character varying(255),
    source_record_kind character varying(255) NOT NULL,
    source_record_id character varying(255) NOT NULL,
    subject_kind character varying(255),
    subject_id character varying(255),
    correlation_key character varying(255),
    spacecraft_id character varying(255),
    source_endpoint_ref character varying(255),
    scheduled_contact_id character varying(255),
    realized_contact_id character varying(255),
    path_id character varying(255),
    capability_instance_id character varying(255),
    activation_id character varying(255),
    actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: mission_model_comparison_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_comparison_reports (
    comparison_report_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    candidate_revision_id character varying(255) NOT NULL,
    baseline_revision_id character varying(255),
    binding_set_id character varying(255),
    binding_set_version integer,
    status character varying(255) NOT NULL,
    risk character varying(255) NOT NULL,
    report_sha256 character varying(255) NOT NULL,
    report jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT mission_model_comparison_reports_binding_set_pair CHECK (((binding_set_id IS NULL) = (binding_set_version IS NULL)))
);


--
-- Name: mission_model_composition_layers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_composition_layers (
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    composition_id character varying(255) NOT NULL,
    layer_id character varying(255) NOT NULL,
    mount character varying(255) NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT mission_model_composition_layers_mount_check CHECK ((((mount)::text ~ '^/([A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+){0,3})?$'::text) AND ((mount)::text !~ '(^|/)\.{1,2}(/|$)'::text))),
    CONSTRAINT mission_model_composition_layers_position_check CHECK ((("position" >= 0) AND ("position" <= 7)))
);


--
-- Name: mission_model_composition_numbers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_composition_numbers (
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    composition_id character varying(255) NOT NULL,
    number integer NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT mission_model_composition_numbers_positive CHECK ((number > 0))
);


--
-- Name: mission_model_compositions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_compositions (
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    composition_id character varying(255) NOT NULL,
    created_by jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mission_model_diagnostics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_diagnostics (
    diagnostic_id character varying(255) NOT NULL,
    revision_id character varying(255) NOT NULL,
    plan_id character varying(255),
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    code character varying(255) NOT NULL,
    severity character varying(255) NOT NULL,
    stage character varying(255) NOT NULL,
    target character varying(255),
    semantic_id character varying(255),
    support character varying(255),
    diagnostic_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mission_model_effective_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_effective_revisions (
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    composition_id character varying(255) NOT NULL,
    authored_head character varying(255),
    compiler_version character varying(255) NOT NULL,
    revision_id character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mission_model_layers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_layers (
    layer_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    layer_kind character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    version integer NOT NULL,
    name character varying(255) NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    declaration_count integer DEFAULT 0 NOT NULL,
    source_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    layer_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mission_model_qualification_cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_qualification_cases (
    qualification_case_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    input_term bytea NOT NULL,
    expected_result_sha256 character varying(255),
    approved_by jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    approved_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: mission_model_revision_layers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_revision_layers (
    revision_id character varying(255) NOT NULL,
    layer_id character varying(255) NOT NULL,
    "position" integer NOT NULL
);


--
-- Name: mission_model_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_revisions (
    revision_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    compiler_version character varying(255) NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    declaration_count integer DEFAULT 0 NOT NULL,
    diagnostic_count integer DEFAULT 0 NOT NULL,
    revision_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    approved_by jsonb,
    approved_at timestamp without time zone,
    rejected_by jsonb,
    rejected_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mission_model_runtime_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_model_runtime_plans (
    plan_id character varying(255) NOT NULL,
    revision_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    target character varying(255) NOT NULL,
    target_contract_version character varying(255) NOT NULL,
    compiler_version character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    plan_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: mission_providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_providers (
    provider_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    provider_type character varying(255) NOT NULL,
    client_key character varying(255) NOT NULL,
    base_url character varying(255) NOT NULL,
    credential_ref character varying(255) NOT NULL,
    environment_ref character varying(255) NOT NULL,
    capabilities_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inventory_sync_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_validated_at timestamp without time zone,
    last_synced_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    provider_account_id character varying(255),
    provider_account_version integer,
    provider_account_grant_id character varying(255),
    provider_account_grant_version integer,
    delivery_policy_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    spacecraft_mappings_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled_service_profile_refs jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    enabled_delivery_profile_refs jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    permitted_resource_refs character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    preferred_transport_refs jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    scheduling_policy_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    fallback_policy_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT mission_providers_complete_account_binding CHECK ((((provider_account_id IS NULL) AND (provider_account_version IS NULL) AND (provider_account_grant_id IS NULL) AND (provider_account_grant_version IS NULL)) OR ((provider_account_id IS NOT NULL) AND (provider_account_version IS NOT NULL) AND (provider_account_grant_id IS NOT NULL) AND (provider_account_grant_version IS NOT NULL))))
);


--
-- Name: mission_source_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_source_endpoints (
    source_endpoint_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    source_ref character varying(255),
    scid integer,
    display_name character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: mission_spacecraft; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_spacecraft (
    spacecraft_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    scid integer,
    spacecraft_type_id character varying(255),
    spacecraft_type_version integer,
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL,
    archived_at timestamp without time zone,
    archived_by jsonb,
    commanding_enabled boolean,
    telemetry_enabled boolean,
    CONSTRAINT mission_spacecraft_lifecycle_check CHECK ((lifecycle_state IN ('active', 'archived')))
);


--
-- Name: mission_spacecraft_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mission_spacecraft_types (
    spacecraft_type_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    downlink_protocol character varying(255) NOT NULL,
    uplink_protocol character varying(255) NOT NULL,
    packet_protocol character varying(255) NOT NULL,
    frame_parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    applications jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    catalog_revision_id character varying(255),
    routing_rules jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    handled_apids integer[]
);


--
-- Name: missions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.missions (
    mission_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    notification_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    title character varying(255) NOT NULL,
    body character varying(255),
    action_url character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: operational_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.operational_events (
    event_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    occurred_at timestamp without time zone NOT NULL,
    recorded_at timestamp without time zone NOT NULL,
    effective_at timestamp without time zone,
    category character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    severity character varying(255),
    subject_kind character varying(255),
    subject_id character varying(255),
    correlation_id character varying(255),
    causation_event_id character varying(255),
    source_record_kind character varying(255),
    source_record_id character varying(255),
    job_id character varying(255),
    replay_run_id character varying(255),
    import_run_id character varying(255),
    actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    scope_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    causality_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    payload_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    previous_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    current_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: ops_dashboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ops_dashboards (
    dashboard_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    document jsonb DEFAULT '{}'::jsonb NOT NULL,
    lock_version integer DEFAULT 1 NOT NULL,
    latest_version integer,
    draft_version integer,
    published_version integer,
    lifecycle_state character varying(255) DEFAULT 'active'::character varying NOT NULL,
    published_at timestamp without time zone,
    published_by character varying(255)
);


--
-- Name: ops_fleet_policy_recoveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ops_fleet_policy_recoveries (
    organization_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    sequence integer DEFAULT 0 NOT NULL,
    operation jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT ops_fleet_policy_sequence_bounds CHECK (((sequence >= 0) AND (sequence <= 1000000)))
);


--
-- Name: organization_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_invitations (
    organization_invitation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    display_name character varying(255),
    membership_role character varying(255) NOT NULL,
    grant_platform_admin boolean DEFAULT false NOT NULL,
    status character varying(255) NOT NULL,
    token_digest character varying(255) NOT NULL,
    token_hint character varying(255) NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    invited_by_user_id character varying(255) NOT NULL,
    accepted_by_user_id character varying(255),
    accepted_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: organization_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_memberships (
    organization_membership_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    role character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    organization_id character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: partition_stream_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partition_stream_keys (
    ordinal bigint NOT NULL,
    mission_id text NOT NULL,
    partition_id text NOT NULL,
    stream_key text NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: partition_stream_keys_ordinal_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partition_stream_keys_ordinal_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partition_stream_keys_ordinal_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partition_stream_keys_ordinal_seq OWNED BY public.partition_stream_keys.ordinal;


--
-- Name: platform_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_events (
    platform_event_id character varying(255) NOT NULL,
    actor_id character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    organization_id character varying(255),
    target_kind character varying(255),
    target_id character varying(255),
    target_label character varying(255),
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp without time zone NOT NULL
);


--
-- Name: protocol_anomalies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_anomalies (
    anomaly_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    spacecraft_id character varying(255),
    protocol_family character varying(255) NOT NULL,
    direction character varying(255) NOT NULL,
    anomaly_kind character varying(255) NOT NULL,
    scid integer,
    vcid integer,
    map_id integer,
    frame_seq integer,
    raw_frame_offset_bytes integer,
    raw_frame_length_bytes integer,
    recorded_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: protocol_archive_quarantine; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_archive_quarantine (
    quarantine_entry_id text NOT NULL,
    mission_id text NOT NULL,
    organization_id text,
    realized_contact_id text,
    spacecraft_id text,
    record_kind text NOT NULL,
    record_id text NOT NULL,
    error_code text NOT NULL,
    error text,
    entry bytea NOT NULL,
    receipt_time timestamp without time zone,
    first_seen_at timestamp without time zone NOT NULL,
    last_seen_at timestamp without time zone NOT NULL,
    last_retry jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: protocol_archive_quarantine_resolutions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_archive_quarantine_resolutions (
    resolution_id text NOT NULL,
    mission_id text NOT NULL,
    item_id text NOT NULL,
    realized_contact_id text,
    spacecraft_id text,
    error_code text NOT NULL,
    action text NOT NULL,
    actor jsonb NOT NULL,
    note text,
    counts jsonb NOT NULL,
    resolved_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: protocol_archive_record_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_archive_record_identities (
    record_kind character varying(255) NOT NULL,
    record_id character varying(255) NOT NULL,
    content_sha256 bytea NOT NULL,
    segment_id bigint NOT NULL
);


--
-- Name: protocol_archive_segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_archive_segments (
    id bigint NOT NULL,
    archive_backend character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    organization_id character varying(255),
    object_key character varying(255) NOT NULL,
    packet_count integer NOT NULL,
    frame_count integer NOT NULL,
    first_receipt_time timestamp without time zone NOT NULL,
    last_receipt_time timestamp without time zone NOT NULL,
    spacecraft_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    realized_contact_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    source_refs character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    evidence_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    frames_by_contact jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: protocol_archive_segments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.protocol_archive_segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: protocol_archive_segments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.protocol_archive_segments_id_seq OWNED BY public.protocol_archive_segments.id;


--
-- Name: protocol_packet_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_packet_records (
    packet_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    protocol_family character varying(255) NOT NULL,
    packet_kind character varying(255) NOT NULL,
    apid integer NOT NULL,
    sequence_flags integer NOT NULL,
    sequence_count integer NOT NULL,
    secondary_header boolean NOT NULL,
    packet_data bytea NOT NULL,
    source_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    source_endpoint_ref character varying(255),
    organization_id character varying(255)
);


--
-- Name: protocol_transfer_frame_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.protocol_transfer_frame_records (
    frame_record_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255),
    spacecraft_id character varying(255),
    protocol_family character varying(255) NOT NULL,
    direction character varying(255) NOT NULL,
    scid integer NOT NULL,
    vcid integer NOT NULL,
    map_id integer,
    frame_seq integer NOT NULL,
    raw_frame_offset_bytes integer NOT NULL,
    raw_frame_length_bytes integer NOT NULL,
    payload_length_bytes integer NOT NULL,
    first_header_pointer integer,
    quality character varying(255),
    source_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: provider_account_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_account_grants (
    provider_account_grant_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    provider_account_id character varying(255) NOT NULL,
    provider_account_version integer NOT NULL,
    version integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    restrictions jsonb DEFAULT '{}'::jsonb NOT NULL,
    granted_by character varying(255),
    granted_at timestamp without time zone NOT NULL,
    grant_reason character varying(255),
    revoked_by character varying(255),
    revoked_at timestamp without time zone,
    revoke_reason character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: provider_account_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_account_versions (
    provider_account_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    version integer NOT NULL,
    provider_type character varying(255) NOT NULL,
    client_key character varying(255) NOT NULL,
    base_url character varying(255) NOT NULL,
    region_ref character varying(255),
    environment_ref character varying(255) NOT NULL,
    credential_ref character varying(255) NOT NULL,
    event_ingestion_mode character varying(255) NOT NULL,
    event_configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    request_policy jsonb DEFAULT '{}'::jsonb NOT NULL,
    guardrails jsonb DEFAULT '{}'::jsonb NOT NULL,
    provider_configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying(255),
    created_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: provider_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_accounts (
    provider_account_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    active_version integer NOT NULL,
    credential_status character varying(255) NOT NULL,
    event_ingestion_status character varying(255) NOT NULL,
    last_validated_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: provider_audit_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_audit_entries (
    provider_audit_entry_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255),
    provider_account_id character varying(255),
    provider_account_grant_id character varying(255),
    provider_id character varying(255),
    provider_reservation_id character varying(255),
    provider_change_id character varying(255),
    contact_id character varying(255),
    scheduled_contact_id character varying(255),
    action character varying(255) NOT NULL,
    outcome character varying(255) NOT NULL,
    provider_occurred_at timestamp without time zone,
    recorded_at timestamp without time zone NOT NULL,
    effective_at timestamp without time zone,
    correlation_id character varying(255),
    request_id character varying(255),
    client_reference character varying(255),
    provider_event_id character varying(255),
    causation_entry_id character varying(255),
    supersedes_entry_id character varying(255),
    credential_ref character varying(255),
    credential_registry_version integer,
    credential_backend_version character varying(255),
    source_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    actor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    previous_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    current_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    decision_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    policy_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    evidence_references jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: provider_change_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_change_approvals (
    provider_change_approval_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    provider_reservation_change_id character varying(255) NOT NULL,
    decision character varying(255) NOT NULL,
    proposal_hash character varying(255) NOT NULL,
    policy_version integer NOT NULL,
    reason character varying(255) NOT NULL,
    actor_user_id character varying(255) NOT NULL,
    actor_document jsonb NOT NULL,
    decided_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT provider_change_approvals_decision_check CHECK ((decision IN ('approved', 'rejected', 'acknowledged')))
);


--
-- Name: provider_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_credentials (
    provider_credential_ref character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    provider_account_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    registry_version integer NOT NULL,
    backend_type character varying(255) NOT NULL,
    backend_key character varying(255) NOT NULL,
    backend_reference character varying(255),
    registered_at timestamp without time zone NOT NULL,
    last_resolved_at timestamp without time zone,
    last_rotated_at timestamp without time zone,
    revoked_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT provider_credentials_backend_type_check CHECK ((backend_type IN ('env', 'external'))),
    CONSTRAINT provider_credentials_registry_version_check CHECK ((registry_version > 0)),
    CONSTRAINT provider_credentials_status_check CHECK ((status IN ('active', 'revoked')))
);


--
-- Name: provider_event_cursors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_event_cursors (
    provider_event_cursor_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    provider_account_id character varying(255) NOT NULL,
    provider_account_version integer NOT NULL,
    environment_ref character varying(255) NOT NULL,
    channel_ref character varying(255) NOT NULL,
    stream_ref character varying(255) NOT NULL,
    cursor_document jsonb DEFAULT '{"value": null}'::jsonb NOT NULL,
    health character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    last_fetched_at timestamp without time zone,
    last_advanced_at timestamp without time zone,
    last_event_at timestamp without time zone,
    lease_owner character varying(255),
    lease_expires_at timestamp without time zone,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: provider_event_inbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_event_inbox (
    provider_event_inbox_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    provider_account_id character varying(255) NOT NULL,
    provider_account_version integer NOT NULL,
    provider_event_cursor_id character varying(255),
    environment_ref character varying(255) NOT NULL,
    channel_ref character varying(255) NOT NULL,
    provider_event_id character varying(255) NOT NULL,
    schema_version character varying(255),
    event_type character varying(255),
    sequence bigint,
    resource_type character varying(255),
    resource_id character varying(255),
    resource_revision bigint,
    request_id character varying(255),
    correlation_id character varying(255),
    client_reference character varying(255),
    provider_occurred_at timestamp without time zone,
    received_at timestamp without time zone NOT NULL,
    payload_document jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    provider_evidence_id character varying(255),
    processing_state character varying(255) NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    last_attempted_at timestamp without time zone,
    processed_at timestamp without time zone,
    error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    identity_collision boolean DEFAULT false NOT NULL,
    mission_id character varying(255),
    provider_id character varying(255),
    provider_reservation_id character varying(255),
    scheduled_contact_id character varying(255),
    contact_id character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: provider_evidence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_evidence (
    provider_evidence_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    provider_account_id character varying(255) NOT NULL,
    storage_kind character varying(255) NOT NULL,
    schema_type character varying(255) NOT NULL,
    media_type character varying(255) NOT NULL,
    captured_at timestamp without time zone NOT NULL,
    byte_count bigint NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    document jsonb,
    external_object_ref character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT provider_evidence_byte_count_check CHECK ((byte_count >= 0)),
    CONSTRAINT provider_evidence_payload_check CHECK (((((storage_kind)::text = 'inline'::text) AND (document IS NOT NULL) AND (external_object_ref IS NULL)) OR (((storage_kind)::text = 'external'::text) AND (document IS NULL) AND (external_object_ref IS NOT NULL)))),
    CONSTRAINT provider_evidence_storage_kind_check CHECK ((storage_kind IN ('inline', 'external')))
);


--
-- Name: provider_reservation_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_reservation_changes (
    provider_reservation_change_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    provider_reservation_id character varying(255) NOT NULL,
    provider_account_id character varying(255),
    provider_account_version integer,
    provider_revision integer NOT NULL,
    from_provider_revision integer NOT NULL,
    change_identity character varying(255) NOT NULL,
    proposal_hash character varying(255) NOT NULL,
    before_snapshot_document jsonb NOT NULL,
    after_snapshot_document jsonb NOT NULL,
    changed_fields_document jsonb NOT NULL,
    classification character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    policy_version integer NOT NULL,
    policy_document jsonb NOT NULL,
    decision_document jsonb NOT NULL,
    actionable boolean DEFAULT false NOT NULL,
    already_effective boolean DEFAULT false NOT NULL,
    deadline_at timestamp without time zone,
    provider_evidence_id character varying(255),
    decided_at timestamp without time zone,
    decided_by character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT provider_reservation_changes_revision_check CHECK (((provider_revision > from_provider_revision) AND (from_provider_revision > 0))),
    CONSTRAINT provider_reservation_changes_state_check CHECK ((lifecycle_state IN ('observed', 'pending_approval', 'policy_accepted', 'approved', 'rejected', 'acknowledgment_required', 'acknowledged', 'configuration_failure', 'superseded', 'apply_failed')))
);


--
-- Name: provider_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_reservations (
    provider_reservation_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    provider_profile_id character varying(255) NOT NULL,
    provider_profile_version integer NOT NULL,
    scheduled_contact_id character varying(255) NOT NULL,
    provider_opportunity_ref character varying(255) NOT NULL,
    provider_contact_ref character varying(255),
    idempotency_key character varying(255) NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    provider_status character varying(255),
    spacecraft_id character varying(255) NOT NULL,
    provider_spacecraft_ref character varying(255) NOT NULL,
    source_endpoint_refs character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    path_template_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    starts_at timestamp without time zone NOT NULL,
    ends_at timestamp without time zone NOT NULL,
    request_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    response_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_error_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    last_reconciled_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    provider_id character varying(255),
    provider_version integer,
    transport_id character varying(255),
    transport_version integer,
    service_profile_ref jsonb DEFAULT '{}'::jsonb NOT NULL,
    delivery_profile_ref jsonb DEFAULT '{}'::jsonb NOT NULL,
    delivery_descriptor_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    pass_phase character varying(255),
    delivery_state character varying(255),
    provider_account_id character varying(255),
    provider_account_version integer,
    provider_account_grant_id character varying(255),
    provider_account_grant_version integer,
    operator_review_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    provider_revision integer DEFAULT 1 NOT NULL,
    requested_snapshot_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    provider_confirmed_snapshot_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    cadence_accepted_snapshot_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    contact_requirement_id character varying(255),
    contact_requirement_version integer,
    contact_plan_id character varying(255),
    contact_plan_version integer,
    contact_opportunity_snapshot_id character varying(255),
    resolution_evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    next_due_at timestamp without time zone,
    CONSTRAINT provider_reservations_complete_account_binding CHECK ((((provider_account_id IS NULL) AND (provider_account_version IS NULL) AND (provider_account_grant_id IS NULL) AND (provider_account_grant_version IS NULL)) OR ((provider_account_id IS NOT NULL) AND (provider_account_version IS NOT NULL) AND (provider_account_grant_id IS NOT NULL) AND (provider_account_grant_version IS NOT NULL)))),
    CONSTRAINT provider_reservations_plan_binding_shape CHECK ((((contact_requirement_id IS NULL) AND (contact_requirement_version IS NULL) AND (contact_plan_id IS NULL) AND (contact_plan_version IS NULL) AND (contact_opportunity_snapshot_id IS NULL)) OR ((contact_requirement_id IS NOT NULL) AND (contact_requirement_version IS NOT NULL) AND (contact_plan_id IS NOT NULL) AND (contact_plan_version IS NOT NULL) AND (contact_opportunity_snapshot_id IS NOT NULL)))),
    CONSTRAINT provider_reservations_provider_revision_positive CHECK ((provider_revision > 0))
)
WITH (fillfactor='85');


--
-- Name: realized_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.realized_contacts (
    realized_contact_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    scheduled_contact_id character varying(255),
    source_endpoint_refs character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    path_documents jsonb DEFAULT '{}'::jsonb NOT NULL,
    clock_mode character varying(255) NOT NULL,
    initial_time timestamp without time zone,
    lifecycle_state character varying(255) NOT NULL,
    realized_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    contact_intents character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL
);


--
-- Name: replay_dispatch_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_dispatch_decisions (
    dispatch_decision_id character varying(255) NOT NULL,
    replay_run_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    packet_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    status character varying(255) NOT NULL,
    matched_rule_ids jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    anomalies jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: replay_dispatch_work_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_dispatch_work_items (
    id bigint NOT NULL,
    dispatch_decision_id character varying(255) NOT NULL,
    binding_rule_id character varying(255) NOT NULL,
    handler_key character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: replay_dispatch_work_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.replay_dispatch_work_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: replay_dispatch_work_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.replay_dispatch_work_items_id_seq OWNED BY public.replay_dispatch_work_items.id;


--
-- Name: replay_managed_action_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_managed_action_requests (
    action_request_id character varying(255) NOT NULL,
    replay_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    action_kind character varying(255) NOT NULL,
    packet_id character varying(255),
    evidence_id character varying(255),
    request_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: replay_managed_capability_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_managed_capability_records (
    capability_record_id character varying(255) NOT NULL,
    replay_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    event_kind character varying(255) NOT NULL,
    packet_id character varying(255),
    evidence_id character varying(255),
    timer_key character varying(255),
    emitted_record_kinds jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    emitted_record_count integer NOT NULL,
    action_request_count integer NOT NULL,
    state_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    recorded_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: replay_managed_timer_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_managed_timer_events (
    timer_event_id character varying(255) NOT NULL,
    replay_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    timer_key character varying(255) NOT NULL,
    event_kind character varying(255) NOT NULL,
    packet_id character varying(255),
    evidence_id character varying(255),
    due_at timestamp without time zone,
    occurred_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: replay_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_runs (
    replay_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    status character varying(255) NOT NULL,
    replayed_evidence_count integer DEFAULT 0 NOT NULL,
    replayed_packet_count integer DEFAULT 0 NOT NULL,
    replayed_sample_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: replay_telemetry_samples; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.replay_telemetry_samples (
    sample_id character varying(255) NOT NULL,
    replay_run_id character varying(255) NOT NULL,
    packet_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    packet_definition_id character varying(255) NOT NULL,
    packet_definition_version integer NOT NULL,
    raw_value jsonb NOT NULL,
    engineering_value jsonb NOT NULL,
    quality_state character varying(255) NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: scheduled_contact_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_contact_revisions (
    scheduled_contact_revision_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    scheduled_contact_id character varying(255) NOT NULL,
    revision integer NOT NULL,
    provider_reservation_change_id character varying(255),
    snapshot_document jsonb NOT NULL,
    reason_document jsonb NOT NULL,
    created_by character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    CONSTRAINT scheduled_contact_revisions_positive CHECK ((revision > 0))
);


--
-- Name: scheduled_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_contacts (
    scheduled_contact_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    source_endpoint_refs character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    path_documents jsonb DEFAULT '{}'::jsonb NOT NULL,
    starts_at timestamp without time zone NOT NULL,
    ends_at timestamp without time zone,
    provider_contact_ref character varying(255),
    lifecycle_state character varying(255) NOT NULL,
    realized_contact_id character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    path_template_ids character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    path_template_ref_documents jsonb DEFAULT '{}'::jsonb NOT NULL,
    link_assignment_ref_documents jsonb DEFAULT '{"items": []}'::jsonb NOT NULL,
    contact_intents character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    current_revision integer DEFAULT 1 NOT NULL,
    CONSTRAINT scheduled_contacts_current_revision_positive CHECK ((current_revision > 0))
);


--
-- Name: scoped_settings_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scoped_settings_revisions (
    revision_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    scope_key character varying(255) NOT NULL,
    section_id character varying(255) NOT NULL,
    version integer NOT NULL,
    document jsonb NOT NULL,
    actor_id character varying(255) NOT NULL,
    actor_name character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT scoped_settings_positive_version CHECK ((version > 0))
);


--
-- Name: semantic_alarm_acknowledgements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_alarm_acknowledgements (
    acknowledgement_id character varying(255) NOT NULL,
    transition_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    actor jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    note text,
    acknowledged_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: semantic_alarm_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_alarm_transitions (
    transition_id character varying(255) NOT NULL,
    evaluation_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    parameter_id character varying(255) NOT NULL,
    policy_id character varying(255) NOT NULL,
    from_state character varying(255) NOT NULL,
    to_state character varying(255) NOT NULL,
    receipt_time timestamp without time zone NOT NULL,
    transition_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: semantic_latest_alarm_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_latest_alarm_states (
    id bigint NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    spacecraft_scope_id character varying(255) DEFAULT ''::character varying NOT NULL,
    spacecraft_id character varying(255),
    parameter_id character varying(255) NOT NULL,
    policy_id character varying(255) NOT NULL,
    evaluation_id character varying(255) NOT NULL,
    transition_id character varying(255),
    effective_state character varying(255) NOT NULL,
    receipt_time timestamp without time zone NOT NULL,
    state_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    generation_time timestamp without time zone
);


--
-- Name: semantic_latest_alarm_states_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.semantic_latest_alarm_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: semantic_latest_alarm_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.semantic_latest_alarm_states_id_seq OWNED BY public.semantic_latest_alarm_states.id;


--
-- Name: semantic_monitoring_evaluations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_monitoring_evaluations (
    evaluation_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    parameter_id character varying(255) NOT NULL,
    policy_id character varying(255) NOT NULL,
    update_id character varying(255) NOT NULL,
    mission_model_revision_id character varying(255) NOT NULL,
    runtime_plan_id character varying(255) NOT NULL,
    evaluated_state character varying(255) NOT NULL,
    effective_state character varying(255) NOT NULL,
    previous_state character varying(255),
    transitioned boolean DEFAULT false NOT NULL,
    matched_context character varying(255),
    violation_count integer DEFAULT 0 NOT NULL,
    conformance_count integer DEFAULT 0 NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    evaluation_document jsonb DEFAULT '{"value": {}}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: semantic_runtime_heads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_runtime_heads (
    organization_scope_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    partition_id character varying(255) NOT NULL,
    runtime_basis_sha256 character varying(255) NOT NULL,
    generation bigint NOT NULL,
    ownership_epoch bigint DEFAULT 0 NOT NULL
);


--
-- Name: semantic_runtime_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_runtime_snapshots (
    organization_scope_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    partition_id character varying(255) NOT NULL,
    runtime_basis_sha256 character varying(255) NOT NULL,
    version integer NOT NULL,
    ownership_epoch bigint NOT NULL,
    state_term bytea NOT NULL,
    resume jsonb DEFAULT '{}'::jsonb NOT NULL,
    integrity_sha256 character varying(255) NOT NULL,
    snapshotted_at timestamp without time zone NOT NULL
);


--
-- Name: service_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_identities (
    service_identity_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255),
    display_name character varying(255) NOT NULL,
    capabilities character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    token_digest character varying(255) NOT NULL,
    token_hint character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: service_identity_accountables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_identity_accountables (
    accountable_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    service_identity_id character varying(255) NOT NULL,
    event character varying(255) NOT NULL,
    actor_kind character varying(255) NOT NULL,
    user_id character varying(255),
    by_service_identity_id character varying(255),
    recorded_by_user_id character varying(255),
    recorded_at timestamp without time zone NOT NULL,
    CONSTRAINT service_identity_accountables_actor CHECK (((((actor_kind)::text = 'user'::text) AND (user_id IS NOT NULL) AND (by_service_identity_id IS NULL)) OR (((actor_kind)::text = 'service'::text) AND (by_service_identity_id IS NOT NULL) AND (user_id IS NULL)))),
    CONSTRAINT service_identity_accountables_event CHECK ((event IN ('issued', 'rotated', 'attributed')))
);


--
-- Name: spacecraft_application_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spacecraft_application_bindings (
    application_binding_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    application_key character varying(255) NOT NULL,
    catalog_revision_id character varying(255) NOT NULL,
    handled_apids integer[] DEFAULT ARRAY[]::integer[] NOT NULL,
    source_endpoint_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    applied_binding_set_id character varying(255),
    applied_binding_set_version integer,
    applied_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    configuration_version integer DEFAULT 1 NOT NULL,
    CONSTRAINT spacecraft_application_bindings_config_version_check CHECK ((configuration_version > 0))
);


--
-- Name: spacecraft_config_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spacecraft_config_overrides (
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    organization_id character varying(255),
    value jsonb NOT NULL,
    reason text,
    set_by jsonb,
    set_in_revision integer,
    set_at timestamp without time zone NOT NULL
);


--
-- Name: spacecraft_configuration_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spacecraft_configuration_revisions (
    configuration_revision_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255) NOT NULL,
    version integer NOT NULL,
    catalog_revision_id character varying(255),
    document jsonb NOT NULL,
    content_sha256 character varying(255) NOT NULL,
    application_basis character varying(255) NOT NULL,
    created_by character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: staged_command_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staged_command_items (
    staged_command_item_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    command_stage_id character varying(255) NOT NULL,
    source_endpoint_ref character varying(255) NOT NULL,
    mission_model_revision_id character varying(255) NOT NULL,
    command_id character varying(255) NOT NULL,
    argument_values_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    priority integer DEFAULT 3 NOT NULL,
    not_before timestamp without time zone,
    expires_at timestamp without time zone,
    notes text,
    item_order integer DEFAULT 0 NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    submitted_command_request_id character varying(255),
    metadata_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: telemetry_backfill_lifecycle_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_backfill_lifecycle_events (
    backfill_lifecycle_event_id character varying(255) NOT NULL,
    backfill_run_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realm character varying(255) NOT NULL,
    replay_run_id character varying(255),
    data_source_id character varying(255),
    binding_id character varying(255),
    observable_id character varying(255),
    point_id character varying(255),
    spacecraft_id character varying(255),
    event_type character varying(255) NOT NULL,
    source_from timestamp without time zone,
    source_to timestamp without time zone,
    receipt_from timestamp without time zone,
    receipt_to timestamp without time zone,
    sample_count integer,
    authority character varying(255) NOT NULL,
    reason text,
    actor_id character varying(255),
    actor_kind character varying(255),
    occurred_at timestamp without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: telemetry_latest_limit_state_rebuild_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_latest_limit_state_rebuild_runs (
    rebuild_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    rebuilt_state_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: telemetry_latest_limit_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_latest_limit_states (
    id bigint NOT NULL,
    limit_event_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_scope_id character varying(255) DEFAULT ''::character varying NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    source_sample_type character varying(255) NOT NULL,
    sample_id character varying(255) NOT NULL,
    limit_definition_id character varying(255) NOT NULL,
    limit_definition_version integer NOT NULL,
    limit_set_name character varying(255) NOT NULL,
    evaluated_value jsonb NOT NULL,
    limit_state character varying(255) NOT NULL,
    normalized_state character varying(255) NOT NULL,
    violation boolean NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: telemetry_latest_limit_states_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.telemetry_latest_limit_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: telemetry_latest_limit_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.telemetry_latest_limit_states_id_seq OWNED BY public.telemetry_latest_limit_states.id;


--
-- Name: telemetry_latest_value_rebuild_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_latest_value_rebuild_runs (
    rebuild_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    rebuilt_value_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: telemetry_latest_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_latest_values (
    id bigint NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_scope_id character varying(255) DEFAULT ''::character varying NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    sample_id character varying(255) NOT NULL,
    packet_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    packet_definition_id character varying(255) NOT NULL,
    packet_definition_version integer NOT NULL,
    raw_value jsonb NOT NULL,
    engineering_value jsonb NOT NULL,
    quality_state character varying(255) NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    realm character varying(255) DEFAULT ''::character varying NOT NULL,
    data_source_id character varying(255) DEFAULT ''::character varying NOT NULL,
    binding_id character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: telemetry_latest_values_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.telemetry_latest_values_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: telemetry_latest_values_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.telemetry_latest_values_id_seq OWNED BY public.telemetry_latest_values.id;


--
-- Name: telemetry_limit_evaluation_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_limit_evaluation_runs (
    limit_run_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    evaluated_sample_count integer DEFAULT 0 NOT NULL,
    emitted_event_count integer DEFAULT 0 NOT NULL,
    definition_count integer DEFAULT 0 NOT NULL,
    failure_reason jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp without time zone NOT NULL,
    completed_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: telemetry_limit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_limit_events (
    limit_event_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    source_sample_type character varying(255) NOT NULL,
    sample_id character varying(255) NOT NULL,
    limit_definition_id character varying(255) NOT NULL,
    limit_definition_version integer NOT NULL,
    limit_set_name character varying(255) NOT NULL,
    evaluated_value jsonb NOT NULL,
    limit_state character varying(255) NOT NULL,
    normalized_state character varying(255) NOT NULL,
    violation boolean NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: telemetry_observation_identity_decision_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_observation_identity_decision_events (
    decision_event_id character varying(255) NOT NULL,
    observation_identity_id character varying(255) NOT NULL,
    organization_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realm character varying(255) NOT NULL,
    replay_run_id character varying(255),
    data_source_id character varying(255),
    binding_id character varying(255),
    observable_id character varying(255) NOT NULL,
    point_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    decision character varying(255) NOT NULL,
    decision_reason character varying(255) NOT NULL,
    actor_id character varying(255),
    actor_kind character varying(255),
    evidence_ref jsonb DEFAULT '{}'::jsonb NOT NULL,
    previous_state jsonb NOT NULL,
    new_state jsonb NOT NULL,
    occurred_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: telemetry_observation_identity_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_observation_identity_states (
    observation_identity_id character varying(255) NOT NULL,
    organization_id character varying(255),
    mission_id character varying(255) NOT NULL,
    realm character varying(255) NOT NULL,
    replay_run_id character varying(255),
    data_source_id character varying(255),
    binding_id character varying(255),
    observable_id character varying(255) NOT NULL,
    point_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    canonical_observation_id character varying(255),
    canonical_sample_id character varying(255),
    canonical_revision integer,
    latest_observation_id character varying(255) NOT NULL,
    latest_sample_id character varying(255) NOT NULL,
    latest_revision integer NOT NULL,
    validity_state character varying(255) NOT NULL,
    canonical_count integer DEFAULT 0 NOT NULL,
    duplicate_count integer DEFAULT 0 NOT NULL,
    conflict_count integer DEFAULT 0 NOT NULL,
    superseded_count integer DEFAULT 0 NOT NULL,
    advisory_count integer DEFAULT 0 NOT NULL,
    first_seen_at timestamp without time zone NOT NULL,
    last_seen_at timestamp without time zone NOT NULL,
    decided_at timestamp without time zone,
    decision_reason character varying(255),
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    decision_event_id character varying(255)
);


--
-- Name: telemetry_samples; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_samples (
    sample_id character varying(255) NOT NULL,
    packet_id character varying(255) NOT NULL,
    evidence_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    spacecraft_id character varying(255),
    point_id character varying(255) NOT NULL,
    point_name character varying(255) NOT NULL,
    packet_definition_id character varying(255) NOT NULL,
    packet_definition_version integer NOT NULL,
    raw_value jsonb NOT NULL,
    engineering_value jsonb NOT NULL,
    quality_state character varying(255) NOT NULL,
    generation_time timestamp without time zone,
    receipt_time timestamp without time zone NOT NULL,
    provenance jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: transport_action_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transport_action_requests (
    action_request_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    path_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    action_kind character varying(255) NOT NULL,
    request_document jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    requested_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255),
    command_release_attempt_id character varying(255),
    command_request_id character varying(255),
    source_endpoint_ref character varying(255),
    command_name character varying(255),
    signal_phase character varying(255),
    reconciliation_evidence jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: transport_capability_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transport_capability_records (
    transport_record_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    path_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    event_kind character varying(255) NOT NULL,
    timer_key character varying(255),
    emitted_record_kinds jsonb DEFAULT '{}'::jsonb NOT NULL,
    emitted_record_count integer NOT NULL,
    action_request_count integer NOT NULL,
    state_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    recorded_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: transport_timer_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transport_timer_events (
    timer_event_id character varying(255) NOT NULL,
    mission_id character varying(255) NOT NULL,
    realized_contact_id character varying(255) NOT NULL,
    path_id character varying(255) NOT NULL,
    capability_instance_id character varying(255) NOT NULL,
    family_key character varying(255) NOT NULL,
    activation_id character varying(255) NOT NULL,
    binding_set_id character varying(255) NOT NULL,
    binding_set_version integer NOT NULL,
    partition_affinity character varying(255) NOT NULL,
    partition_value character varying(255) NOT NULL,
    timer_key character varying(255) NOT NULL,
    event_kind character varying(255) NOT NULL,
    due_at timestamp without time zone,
    occurred_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    organization_id character varying(255)
);


--
-- Name: user_local_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_local_credentials (
    local_credential_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    provider_key character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    password_salt character varying(255) NOT NULL,
    password_iterations integer NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: user_session_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_session_tokens (
    session_token_id character varying(255) NOT NULL,
    user_id character varying(255) NOT NULL,
    context character varying(255) NOT NULL,
    token_digest character varying(255) NOT NULL,
    token_hint character varying(255) NOT NULL,
    expires_at timestamp without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    user_id character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    capabilities character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    lifecycle_state character varying(255) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    confirmed_at timestamp without time zone
);


--
-- Name: application_dispatch_work_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dispatch_work_items ALTER COLUMN id SET DEFAULT nextval('public.application_dispatch_work_items_id_seq'::regclass);


--
-- Name: comms_routing_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_routing_rules ALTER COLUMN id SET DEFAULT nextval('public.comms_routing_rules_id_seq'::regclass);


--
-- Name: derived_telemetry_latest_values id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_latest_values ALTER COLUMN id SET DEFAULT nextval('public.derived_telemetry_latest_values_id_seq'::regclass);


--
-- Name: federated_application_action_idempotencies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.federated_application_action_idempotencies ALTER COLUMN id SET DEFAULT nextval('public.federated_application_action_idempotencies_id_seq'::regclass);


--
-- Name: governed_binding_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_binding_rules ALTER COLUMN id SET DEFAULT nextval('public.governed_binding_rules_id_seq'::regclass);


--
-- Name: governed_binding_sets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_binding_sets ALTER COLUMN id SET DEFAULT nextval('public.governed_binding_sets_id_seq'::regclass);


--
-- Name: governed_capability_instances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_capability_instances ALTER COLUMN id SET DEFAULT nextval('public.governed_capability_instances_id_seq'::regclass);


--
-- Name: governed_derived_telemetry_definitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_derived_telemetry_definitions ALTER COLUMN id SET DEFAULT nextval('public.governed_derived_telemetry_definitions_id_seq'::regclass);


--
-- Name: governed_limit_definitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_limit_definitions ALTER COLUMN id SET DEFAULT nextval('public.governed_limit_definitions_id_seq'::regclass);


--
-- Name: governed_packet_definition_fields id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_packet_definition_fields ALTER COLUMN id SET DEFAULT nextval('public.governed_packet_definition_fields_id_seq'::regclass);


--
-- Name: governed_packet_definitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_packet_definitions ALTER COLUMN id SET DEFAULT nextval('public.governed_packet_definitions_id_seq'::regclass);


--
-- Name: partition_stream_keys ordinal; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partition_stream_keys ALTER COLUMN ordinal SET DEFAULT nextval('public.partition_stream_keys_ordinal_seq'::regclass);


--
-- Name: protocol_archive_segments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_archive_segments ALTER COLUMN id SET DEFAULT nextval('public.protocol_archive_segments_id_seq'::regclass);


--
-- Name: replay_dispatch_work_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_dispatch_work_items ALTER COLUMN id SET DEFAULT nextval('public.replay_dispatch_work_items_id_seq'::regclass);


--
-- Name: semantic_latest_alarm_states id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_latest_alarm_states ALTER COLUMN id SET DEFAULT nextval('public.semantic_latest_alarm_states_id_seq'::regclass);


--
-- Name: telemetry_latest_limit_states id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_limit_states ALTER COLUMN id SET DEFAULT nextval('public.telemetry_latest_limit_states_id_seq'::regclass);


--
-- Name: telemetry_latest_values id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_values ALTER COLUMN id SET DEFAULT nextval('public.telemetry_latest_values_id_seq'::regclass);


--
-- Name: account_events account_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_events
    ADD CONSTRAINT account_events_pkey PRIMARY KEY (account_event_id);


--
-- Name: activation_decisions activation_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_decisions
    ADD CONSTRAINT activation_decisions_pkey PRIMARY KEY (activation_decision_id);


--
-- Name: activation_executions activation_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_executions
    ADD CONSTRAINT activation_executions_pkey PRIMARY KEY (activation_execution_id);


--
-- Name: activation_fleet_entries activation_fleet_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_fleet_entries
    ADD CONSTRAINT activation_fleet_entries_pkey PRIMARY KEY (mission_id, entry_sha256);


--
-- Name: activation_fleet_members activation_fleet_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_fleet_members
    ADD CONSTRAINT activation_fleet_members_pkey PRIMARY KEY (mission_id, fleet_sha256, spacecraft_id);


--
-- Name: activation_fleets activation_fleets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_fleets
    ADD CONSTRAINT activation_fleets_pkey PRIMARY KEY (mission_id, fleet_sha256);


--
-- Name: activation_requests activation_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_requests
    ADD CONSTRAINT activation_requests_pkey PRIMARY KEY (activation_request_id);


--
-- Name: active_limit_definitions active_limit_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_limit_definitions
    ADD CONSTRAINT active_limit_definitions_pkey PRIMARY KEY (definition_activation_key);


--
-- Name: alarm_episode_events alarm_episode_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alarm_episode_events
    ADD CONSTRAINT alarm_episode_events_pkey PRIMARY KEY (event_id);


--
-- Name: alarm_episodes alarm_episodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alarm_episodes
    ADD CONSTRAINT alarm_episodes_pkey PRIMARY KEY (episode_id);


--
-- Name: application_dispatch_decisions application_dispatch_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dispatch_decisions
    ADD CONSTRAINT application_dispatch_decisions_pkey PRIMARY KEY (dispatch_decision_id);


--
-- Name: application_dispatch_work_items application_dispatch_work_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dispatch_work_items
    ADD CONSTRAINT application_dispatch_work_items_pkey PRIMARY KEY (id);


--
-- Name: application_installation_events application_installation_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_installation_events
    ADD CONSTRAINT application_installation_events_pkey PRIMARY KEY (application_installation_event_id);


--
-- Name: application_installations application_installations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_installations
    ADD CONSTRAINT application_installations_pkey PRIMARY KEY (application_installation_id);


--
-- Name: application_packet_binding_configurations application_packet_binding_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_binding_configurations
    ADD CONSTRAINT application_packet_binding_configurations_pkey PRIMARY KEY (packet_binding_configuration_id);


--
-- Name: application_packet_binding_resources application_packet_binding_resources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_binding_resources
    ADD CONSTRAINT application_packet_binding_resources_pkey PRIMARY KEY (packet_binding_resource_id);


--
-- Name: application_packet_bindings application_packet_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_bindings
    ADD CONSTRAINT application_packet_bindings_pkey PRIMARY KEY (packet_binding_id);


--
-- Name: automation_grant_decisions automation_grant_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_grant_decisions
    ADD CONSTRAINT automation_grant_decisions_pkey PRIMARY KEY (automation_grant_decision_id);


--
-- Name: automation_grant_operations automation_grant_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_grant_operations
    ADD CONSTRAINT automation_grant_operations_pkey PRIMARY KEY (automation_grant_operation_id);


--
-- Name: automation_grants automation_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_grants
    ADD CONSTRAINT automation_grants_pkey PRIMARY KEY (automation_grant_id);


--
-- Name: background_jobs background_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.background_jobs
    ADD CONSTRAINT background_jobs_pkey PRIMARY KEY (job_id);


--
-- Name: booking_resolutions booking_resolutions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_resolutions
    ADD CONSTRAINT booking_resolutions_pkey PRIMARY KEY (booking_resolution_id);


--
-- Name: catalog_artifacts catalog_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_artifacts
    ADD CONSTRAINT catalog_artifacts_pkey PRIMARY KEY (artifact_id);


--
-- Name: catalog_databases catalog_databases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_databases
    ADD CONSTRAINT catalog_databases_pkey PRIMARY KEY (catalog_database_id);


--
-- Name: catalog_import_runs catalog_import_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_import_runs
    ADD CONSTRAINT catalog_import_runs_pkey PRIMARY KEY (import_run_id);


--
-- Name: catalog_revisions catalog_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_pkey PRIMARY KEY (catalog_revision_id);


--
-- Name: combined_downlink_records combined_downlink_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.combined_downlink_records
    ADD CONSTRAINT combined_downlink_records_pkey PRIMARY KEY (merged_record_id);


--
-- Name: command_approvals command_approvals_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_approvals
    ADD CONSTRAINT command_approvals_org_scope_idx_uniq UNIQUE (organization_id, mission_id, command_approval_id);


--
-- Name: command_approvals command_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_approvals
    ADD CONSTRAINT command_approvals_pkey PRIMARY KEY (command_approval_id);


--
-- Name: command_approvals command_approvals_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_approvals
    ADD CONSTRAINT command_approvals_scope_idx_uniq UNIQUE (mission_id, command_approval_id);


--
-- Name: command_group_events command_group_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_group_events
    ADD CONSTRAINT command_group_events_pkey PRIMARY KEY (event_id);


--
-- Name: command_groups command_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_groups
    ADD CONSTRAINT command_groups_pkey PRIMARY KEY (command_group_id);


--
-- Name: command_queue_entries command_queue_entries_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_queue_entries
    ADD CONSTRAINT command_queue_entries_org_scope_idx_uniq UNIQUE (organization_id, mission_id, command_queue_entry_id);


--
-- Name: command_queue_entries command_queue_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_queue_entries
    ADD CONSTRAINT command_queue_entries_pkey PRIMARY KEY (command_queue_entry_id);


--
-- Name: command_queue_entries command_queue_entries_request_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_queue_entries
    ADD CONSTRAINT command_queue_entries_request_org_scope_idx_uniq UNIQUE (organization_id, mission_id, command_request_id);


--
-- Name: command_queue_entries command_queue_entries_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_queue_entries
    ADD CONSTRAINT command_queue_entries_scope_idx_uniq UNIQUE (mission_id, command_queue_entry_id);


--
-- Name: command_release_attempts command_release_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_release_attempts
    ADD CONSTRAINT command_release_attempts_pkey PRIMARY KEY (command_release_attempt_id);


--
-- Name: command_requests command_requests_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_requests
    ADD CONSTRAINT command_requests_org_scope_idx_uniq UNIQUE (organization_id, mission_id, command_request_id);


--
-- Name: command_requests command_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_requests
    ADD CONSTRAINT command_requests_pkey PRIMARY KEY (command_request_id);


--
-- Name: command_requests command_requests_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_requests
    ADD CONSTRAINT command_requests_scope_idx_uniq UNIQUE (mission_id, command_request_id);


--
-- Name: command_stages command_stages_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_stages
    ADD CONSTRAINT command_stages_org_scope_idx_uniq UNIQUE (organization_id, mission_id, command_stage_id);


--
-- Name: command_stages command_stages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_stages
    ADD CONSTRAINT command_stages_pkey PRIMARY KEY (command_stage_id);


--
-- Name: command_stages command_stages_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_stages
    ADD CONSTRAINT command_stages_scope_idx_uniq UNIQUE (mission_id, command_stage_id);


--
-- Name: command_verifier_instances command_verifier_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_verifier_instances
    ADD CONSTRAINT command_verifier_instances_pkey PRIMARY KEY (command_verifier_instance_id);


--
-- Name: comms_routing_rule_events comms_routing_rule_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_routing_rule_events
    ADD CONSTRAINT comms_routing_rule_events_pkey PRIMARY KEY (routing_rule_event_id);


--
-- Name: comms_routing_rules comms_routing_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_routing_rules
    ADD CONSTRAINT comms_routing_rules_pkey PRIMARY KEY (id);


--
-- Name: contact_actions contact_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_actions
    ADD CONSTRAINT contact_actions_pkey PRIMARY KEY (contact_action_id);


--
-- Name: contact_opportunity_snapshots contact_opportunity_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_pkey PRIMARY KEY (contact_opportunity_snapshot_id);


--
-- Name: contact_pass_results contact_pass_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_pass_results
    ADD CONSTRAINT contact_pass_results_pkey PRIMARY KEY (provider_reservation_id);


--
-- Name: contact_plan_approvals contact_plan_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_approvals
    ADD CONSTRAINT contact_plan_approvals_pkey PRIMARY KEY (contact_plan_approval_id);


--
-- Name: contact_plan_execution_items contact_plan_execution_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_pkey PRIMARY KEY (contact_plan_execution_item_id);


--
-- Name: contact_plan_operations contact_plan_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_operations
    ADD CONSTRAINT contact_plan_operations_pkey PRIMARY KEY (contact_plan_operation_id);


--
-- Name: contact_plan_opportunity_refs contact_plan_opportunity_refs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_opportunity_refs
    ADD CONSTRAINT contact_plan_opportunity_refs_pkey PRIMARY KEY (contact_plan_opportunity_ref_id);


--
-- Name: contact_plan_requirement_refs contact_plan_requirement_refs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_requirement_refs
    ADD CONSTRAINT contact_plan_requirement_refs_pkey PRIMARY KEY (contact_plan_requirement_ref_id);


--
-- Name: contact_plan_run_refs contact_plan_run_refs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_run_refs
    ADD CONSTRAINT contact_plan_run_refs_pkey PRIMARY KEY (contact_plan_run_ref_id);


--
-- Name: contact_plan_submissions contact_plan_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_submissions
    ADD CONSTRAINT contact_plan_submissions_pkey PRIMARY KEY (contact_plan_submission_id);


--
-- Name: contact_plan_versions contact_plan_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_versions
    ADD CONSTRAINT contact_plan_versions_pkey PRIMARY KEY (contact_plan_version_id);


--
-- Name: contact_plan_versions contact_plan_versions_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_versions
    ADD CONSTRAINT contact_plan_versions_scope_uniq UNIQUE (organization_id, mission_id, contact_plan_id, version);


--
-- Name: contact_planning_runs contact_planning_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_planning_runs
    ADD CONSTRAINT contact_planning_runs_pkey PRIMARY KEY (contact_planning_run_id);


--
-- Name: contact_planning_searches contact_planning_searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_planning_searches
    ADD CONSTRAINT contact_planning_searches_pkey PRIMARY KEY (contact_planning_search_id);


--
-- Name: contact_plans contact_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plans
    ADD CONSTRAINT contact_plans_pkey PRIMARY KEY (contact_plan_id);


--
-- Name: contact_plans contact_plans_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plans
    ADD CONSTRAINT contact_plans_scope_uniq UNIQUE (organization_id, mission_id, contact_plan_id);


--
-- Name: contact_requirement_occurrences contact_requirement_occurrences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_pkey PRIMARY KEY (contact_requirement_occurrence_id);


--
-- Name: contact_requirement_template_versions contact_requirement_template_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_pkey PRIMARY KEY (contact_requirement_template_version_id);


--
-- Name: contact_requirement_template_versions contact_requirement_template_versions_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_scope_uniq UNIQUE (organization_id, mission_id, contact_requirement_template_id, version);


--
-- Name: contact_requirement_templates contact_requirement_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_pkey PRIMARY KEY (contact_requirement_template_id);


--
-- Name: contact_requirement_templates contact_requirement_templates_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_scope_uniq UNIQUE (organization_id, mission_id, contact_requirement_template_id);


--
-- Name: contact_requirement_versions contact_requirement_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_pkey PRIMARY KEY (contact_requirement_version_id);


--
-- Name: contact_requirement_versions contact_requirement_versions_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_scope_uniq UNIQUE (organization_id, mission_id, contact_requirement_id, version);


--
-- Name: contact_requirements contact_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirements
    ADD CONSTRAINT contact_requirements_pkey PRIMARY KEY (contact_requirement_id);


--
-- Name: contact_requirements contact_requirements_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirements
    ADD CONSTRAINT contact_requirements_scope_uniq UNIQUE (organization_id, mission_id, contact_requirement_id);


--
-- Name: contact_schedule_operations contact_schedule_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_schedule_operations
    ADD CONSTRAINT contact_schedule_operations_pkey PRIMARY KEY (operation_id);


--
-- Name: dashboard_deployments dashboard_deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_deployments
    ADD CONSTRAINT dashboard_deployments_pkey PRIMARY KEY (dashboard_deployment_id);


--
-- Name: dashboard_investigation_presets dashboard_investigation_presets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_investigation_presets
    ADD CONSTRAINT dashboard_investigation_presets_pkey PRIMARY KEY (dashboard_investigation_preset_id);


--
-- Name: dashboard_library_items dashboard_library_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_library_items
    ADD CONSTRAINT dashboard_library_items_pkey PRIMARY KEY (dashboard_library_item_id);


--
-- Name: dashboard_library_versions dashboard_library_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_library_versions
    ADD CONSTRAINT dashboard_library_versions_pkey PRIMARY KEY (dashboard_library_version_id);


--
-- Name: dashboard_lifecycle_events dashboard_lifecycle_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_lifecycle_events
    ADD CONSTRAINT dashboard_lifecycle_events_pkey PRIMARY KEY (dashboard_lifecycle_event_id);


--
-- Name: dashboard_playlists dashboard_playlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_playlists
    ADD CONSTRAINT dashboard_playlists_pkey PRIMARY KEY (dashboard_playlist_id);


--
-- Name: dashboard_runtime_invalidation_decision_events dashboard_runtime_invalidation_decision_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_runtime_invalidation_decision_events
    ADD CONSTRAINT dashboard_runtime_invalidation_decision_events_pkey PRIMARY KEY (dashboard_runtime_invalidation_decision_event_id);


--
-- Name: dashboard_shares dashboard_shares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_shares
    ADD CONSTRAINT dashboard_shares_pkey PRIMARY KEY (dashboard_share_id);


--
-- Name: dashboard_snapshots dashboard_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT dashboard_snapshots_pkey PRIMARY KEY (dashboard_snapshot_id);


--
-- Name: dashboard_user_preferences dashboard_user_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_pkey PRIMARY KEY (dashboard_user_preference_id);


--
-- Name: dashboard_versions dashboard_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_versions
    ADD CONSTRAINT dashboard_versions_pkey PRIMARY KEY (dashboard_version_id);


--
-- Name: data_source_binding_events data_source_binding_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_binding_events
    ADD CONSTRAINT data_source_binding_events_pkey PRIMARY KEY (data_binding_event_id);


--
-- Name: data_source_bindings data_source_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_bindings
    ADD CONSTRAINT data_source_bindings_pkey PRIMARY KEY (binding_id);


--
-- Name: data_source_credential_events data_source_credential_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_pkey PRIMARY KEY (source_credential_event_id);


--
-- Name: data_source_credential_references data_source_credential_references_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_references
    ADD CONSTRAINT data_source_credential_references_pkey PRIMARY KEY (credentials_ref);


--
-- Name: data_source_definition_events data_source_definition_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_pkey PRIMARY KEY (data_source_event_id);


--
-- Name: data_source_definitions data_source_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definitions
    ADD CONSTRAINT data_source_definitions_pkey PRIMARY KEY (data_source_id);


--
-- Name: data_source_health_events data_source_health_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_health_events
    ADD CONSTRAINT data_source_health_events_pkey PRIMARY KEY (source_health_event_id);


--
-- Name: data_source_health_statuses data_source_health_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_health_statuses
    ADD CONSTRAINT data_source_health_statuses_pkey PRIMARY KEY (source_health_key);


--
-- Name: data_source_watermark_events data_source_watermark_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_watermark_events
    ADD CONSTRAINT data_source_watermark_events_pkey PRIMARY KEY (source_watermark_event_id);


--
-- Name: data_source_watermark_statuses data_source_watermark_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_watermark_statuses
    ADD CONSTRAINT data_source_watermark_statuses_pkey PRIMARY KEY (source_watermark_key);


--
-- Name: derived_telemetry_evaluation_runs derived_telemetry_evaluation_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_evaluation_runs
    ADD CONSTRAINT derived_telemetry_evaluation_runs_pkey PRIMARY KEY (derived_run_id);


--
-- Name: derived_telemetry_latest_value_rebuild_runs derived_telemetry_latest_value_rebuild_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_latest_value_rebuild_runs
    ADD CONSTRAINT derived_telemetry_latest_value_rebuild_runs_pkey PRIMARY KEY (rebuild_run_id);


--
-- Name: derived_telemetry_latest_values derived_telemetry_latest_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_latest_values
    ADD CONSTRAINT derived_telemetry_latest_values_pkey PRIMARY KEY (id);


--
-- Name: derived_telemetry_samples derived_telemetry_samples_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_samples
    ADD CONSTRAINT derived_telemetry_samples_pkey PRIMARY KEY (derived_sample_id);


--
-- Name: downlink_diagnostics downlink_diagnostics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downlink_diagnostics
    ADD CONSTRAINT downlink_diagnostics_pkey PRIMARY KEY (diagnostic_id);


--
-- Name: downlink_observations downlink_observations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downlink_observations
    ADD CONSTRAINT downlink_observations_pkey PRIMARY KEY (observation_id);


--
-- Name: federated_application_action_idempotencies federated_application_action_idempotencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.federated_application_action_idempotencies
    ADD CONSTRAINT federated_application_action_idempotencies_pkey PRIMARY KEY (id);


--
-- Name: fleet_automation_actions fleet_automation_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_pkey PRIMARY KEY (fleet_automation_action_id);


--
-- Name: fleet_planning_decisions fleet_planning_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_decisions
    ADD CONSTRAINT fleet_planning_decisions_pkey PRIMARY KEY (fleet_planning_decision_id);


--
-- Name: fleet_planning_policies fleet_planning_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_pkey PRIMARY KEY (fleet_planning_policy_id);


--
-- Name: fleet_planning_policies fleet_planning_policies_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_scope_uniq UNIQUE (organization_id, mission_id, fleet_planning_policy_id);


--
-- Name: fleet_planning_policy_approvals fleet_planning_policy_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policy_approvals
    ADD CONSTRAINT fleet_planning_policy_approvals_pkey PRIMARY KEY (fleet_planning_policy_approval_id);


--
-- Name: fleet_planning_policy_versions fleet_planning_policy_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policy_versions
    ADD CONSTRAINT fleet_planning_policy_versions_pkey PRIMARY KEY (fleet_planning_policy_version_id);


--
-- Name: fleet_planning_policy_versions fleet_planning_policy_versions_scope_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policy_versions
    ADD CONSTRAINT fleet_planning_policy_versions_scope_uniq UNIQUE (organization_id, mission_id, fleet_planning_policy_id, version);


--
-- Name: fleet_planning_run_requirement_refs fleet_planning_run_requirement_refs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_pkey PRIMARY KEY (fleet_planning_run_requirement_ref_id);


--
-- Name: fleet_planning_runs fleet_planning_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_pkey PRIMARY KEY (fleet_planning_run_id);


--
-- Name: frontend_release_catalog_bindings frcb_identity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_bindings
    ADD CONSTRAINT frcb_identity_pkey PRIMARY KEY (generation_id, application_id, application_version, package_id, package_version, surface_id, surface_version);


--
-- Name: frontend_release_activation_controls frontend_release_activation_controls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_activation_controls
    ADD CONSTRAINT frontend_release_activation_controls_pkey PRIMARY KEY (control_id);


--
-- Name: frontend_release_activation_requests frontend_release_activation_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_activation_requests
    ADD CONSTRAINT frontend_release_activation_requests_pkey PRIMARY KEY (request_id);


--
-- Name: frontend_release_artifacts frontend_release_artifacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_artifacts
    ADD CONSTRAINT frontend_release_artifacts_pkey PRIMARY KEY (artifact_id);


--
-- Name: frontend_release_catalog_generations frontend_release_catalog_generations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_generations
    ADD CONSTRAINT frontend_release_catalog_generations_pkey PRIMARY KEY (generation_id);


--
-- Name: frontend_release_catalog_publications frontend_release_catalog_publications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_publications
    ADD CONSTRAINT frontend_release_catalog_publications_pkey PRIMARY KEY (publication_id);


--
-- Name: frontend_release_objects frontend_release_objects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_objects
    ADD CONSTRAINT frontend_release_objects_pkey PRIMARY KEY (sha256);


--
-- Name: frontend_release_publications frontend_release_publications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_publications
    ADD CONSTRAINT frontend_release_publications_pkey PRIMARY KEY (publication_id);


--
-- Name: frontend_release_staged_objects frontend_release_staged_objects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_staged_objects
    ADD CONSTRAINT frontend_release_staged_objects_pkey PRIMARY KEY (sha256);


--
-- Name: governed_binding_rules governed_binding_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_binding_rules
    ADD CONSTRAINT governed_binding_rules_pkey PRIMARY KEY (id);


--
-- Name: governed_binding_sets governed_binding_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_binding_sets
    ADD CONSTRAINT governed_binding_sets_pkey PRIMARY KEY (id);


--
-- Name: governed_capability_instances governed_capability_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_capability_instances
    ADD CONSTRAINT governed_capability_instances_pkey PRIMARY KEY (id);


--
-- Name: governed_derived_telemetry_definitions governed_derived_telemetry_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_derived_telemetry_definitions
    ADD CONSTRAINT governed_derived_telemetry_definitions_pkey PRIMARY KEY (id);


--
-- Name: governed_limit_definitions governed_limit_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_limit_definitions
    ADD CONSTRAINT governed_limit_definitions_pkey PRIMARY KEY (id);


--
-- Name: governed_packet_definition_fields governed_packet_definition_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_packet_definition_fields
    ADD CONSTRAINT governed_packet_definition_fields_pkey PRIMARY KEY (id);


--
-- Name: governed_packet_definitions governed_packet_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_packet_definitions
    ADD CONSTRAINT governed_packet_definitions_pkey PRIMARY KEY (id);


--
-- Name: ground_station_availability_windows ground_station_availability_windows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ground_station_availability_windows
    ADD CONSTRAINT ground_station_availability_windows_pkey PRIMARY KEY (window_id);


--
-- Name: ingress_archive_evidence_entries ingress_archive_evidence_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingress_archive_evidence_entries
    ADD CONSTRAINT ingress_archive_evidence_entries_pkey PRIMARY KEY (evidence_id);


--
-- Name: ingress_raw_evidence ingress_raw_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingress_raw_evidence
    ADD CONSTRAINT ingress_raw_evidence_pkey PRIMARY KEY (evidence_id);


--
-- Name: job_outcome_resolutions job_outcome_resolutions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_outcome_resolutions
    ADD CONSTRAINT job_outcome_resolutions_pkey PRIMARY KEY (item_id);


--
-- Name: limit_definition_lifecycle_events limit_definition_lifecycle_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.limit_definition_lifecycle_events
    ADD CONSTRAINT limit_definition_lifecycle_events_pkey PRIMARY KEY (limit_definition_lifecycle_event_id);


--
-- Name: managed_action_requests managed_action_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.managed_action_requests
    ADD CONSTRAINT managed_action_requests_pkey PRIMARY KEY (action_request_id);


--
-- Name: managed_capability_records managed_capability_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.managed_capability_records
    ADD CONSTRAINT managed_capability_records_pkey PRIMARY KEY (capability_record_id);


--
-- Name: managed_timer_events managed_timer_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.managed_timer_events
    ADD CONSTRAINT managed_timer_events_pkey PRIMARY KEY (timer_event_id);


--
-- Name: mission_active_binding_sets mission_active_binding_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_active_binding_sets
    ADD CONSTRAINT mission_active_binding_sets_pkey PRIMARY KEY (mission_id);


--
-- Name: mission_binding_set_activations mission_binding_set_activations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_binding_set_activations
    ADD CONSTRAINT mission_binding_set_activations_pkey PRIMARY KEY (activation_id);


--
-- Name: mission_config_change_sets mission_config_change_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_change_sets
    ADD CONSTRAINT mission_config_change_sets_pkey PRIMARY KEY (change_set_id);


--
-- Name: mission_config_changes mission_config_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_changes
    ADD CONSTRAINT mission_config_changes_pkey PRIMARY KEY (change_id);


--
-- Name: mission_config_heads mission_config_heads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_heads
    ADD CONSTRAINT mission_config_heads_pkey PRIMARY KEY (mission_id);


--
-- Name: mission_config_ops mission_config_ops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_ops
    ADD CONSTRAINT mission_config_ops_pkey PRIMARY KEY (op_id);


--
-- Name: mission_config_reviews mission_config_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_reviews
    ADD CONSTRAINT mission_config_reviews_pkey PRIMARY KEY (review_id);


--
-- Name: mission_config_revision_entries mission_config_revision_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_revision_entries
    ADD CONSTRAINT mission_config_revision_entries_pkey PRIMARY KEY (entry_id);


--
-- Name: mission_config_revisions mission_config_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_revisions
    ADD CONSTRAINT mission_config_revisions_pkey PRIMARY KEY (revision_id);


--
-- Name: mission_event_rebuild_runs mission_event_rebuild_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_event_rebuild_runs
    ADD CONSTRAINT mission_event_rebuild_runs_pkey PRIMARY KEY (rebuild_run_id);


--
-- Name: mission_events mission_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_events
    ADD CONSTRAINT mission_events_pkey PRIMARY KEY (mission_event_id);


--
-- Name: mission_model_comparison_reports mission_model_comparison_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_comparison_reports
    ADD CONSTRAINT mission_model_comparison_reports_pkey PRIMARY KEY (comparison_report_id);


--
-- Name: mission_model_composition_layers mission_model_composition_layers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_composition_layers
    ADD CONSTRAINT mission_model_composition_layers_pkey PRIMARY KEY (organization_id, mission_id, composition_id, layer_id);


--
-- Name: mission_model_composition_numbers mission_model_composition_numbers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_composition_numbers
    ADD CONSTRAINT mission_model_composition_numbers_pkey PRIMARY KEY (organization_id, mission_id, composition_id);


--
-- Name: mission_model_compositions mission_model_compositions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_compositions
    ADD CONSTRAINT mission_model_compositions_pkey PRIMARY KEY (organization_id, mission_id, composition_id);


--
-- Name: mission_model_diagnostics mission_model_diagnostics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_diagnostics
    ADD CONSTRAINT mission_model_diagnostics_pkey PRIMARY KEY (diagnostic_id);


--
-- Name: mission_model_layers mission_model_layers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_layers
    ADD CONSTRAINT mission_model_layers_pkey PRIMARY KEY (layer_id);


--
-- Name: mission_model_qualification_cases mission_model_qualification_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_qualification_cases
    ADD CONSTRAINT mission_model_qualification_cases_pkey PRIMARY KEY (qualification_case_id);


--
-- Name: mission_model_revision_layers mission_model_revision_layers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_revision_layers
    ADD CONSTRAINT mission_model_revision_layers_pkey PRIMARY KEY (revision_id, layer_id);


--
-- Name: mission_model_revisions mission_model_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_revisions
    ADD CONSTRAINT mission_model_revisions_pkey PRIMARY KEY (revision_id);


--
-- Name: mission_model_runtime_plans mission_model_runtime_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_runtime_plans
    ADD CONSTRAINT mission_model_runtime_plans_pkey PRIMARY KEY (plan_id);


--
-- Name: mission_source_endpoints mission_source_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_source_endpoints
    ADD CONSTRAINT mission_source_endpoints_pkey PRIMARY KEY (source_endpoint_id);


--
-- Name: mission_spacecraft mission_spacecraft_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_org_scope_idx_uniq UNIQUE (organization_id, mission_id, spacecraft_id);


--
-- Name: mission_spacecraft mission_spacecraft_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_pkey PRIMARY KEY (spacecraft_id);


--
-- Name: mission_spacecraft mission_spacecraft_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_scope_idx_uniq UNIQUE (mission_id, spacecraft_id);


--
-- Name: missions missions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.missions
    ADD CONSTRAINT missions_pkey PRIMARY KEY (mission_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (notification_id);


--
-- Name: operational_events operational_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.operational_events
    ADD CONSTRAINT operational_events_pkey PRIMARY KEY (event_id);


--
-- Name: ops_dashboards ops_dashboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_dashboards
    ADD CONSTRAINT ops_dashboards_pkey PRIMARY KEY (dashboard_id);


--
-- Name: ops_fleet_policy_recoveries ops_fleet_policy_recoveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_fleet_policy_recoveries
    ADD CONSTRAINT ops_fleet_policy_recoveries_pkey PRIMARY KEY (organization_id, user_id, mission_id);


--
-- Name: organization_invitations organization_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_invitations
    ADD CONSTRAINT organization_invitations_pkey PRIMARY KEY (organization_invitation_id);


--
-- Name: organization_memberships organization_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_pkey PRIMARY KEY (organization_membership_id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (organization_id);


--
-- Name: partition_stream_keys partition_stream_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partition_stream_keys
    ADD CONSTRAINT partition_stream_keys_pkey PRIMARY KEY (ordinal);


--
-- Name: platform_events platform_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_events
    ADD CONSTRAINT platform_events_pkey PRIMARY KEY (platform_event_id);


--
-- Name: protocol_anomalies protocol_anomalies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_anomalies
    ADD CONSTRAINT protocol_anomalies_pkey PRIMARY KEY (anomaly_id);


--
-- Name: protocol_archive_quarantine protocol_archive_quarantine_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_archive_quarantine
    ADD CONSTRAINT protocol_archive_quarantine_pkey PRIMARY KEY (quarantine_entry_id);


--
-- Name: protocol_archive_quarantine_resolutions protocol_archive_quarantine_resolutions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_archive_quarantine_resolutions
    ADD CONSTRAINT protocol_archive_quarantine_resolutions_pkey PRIMARY KEY (resolution_id);


--
-- Name: protocol_archive_record_identities protocol_archive_record_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_archive_record_identities
    ADD CONSTRAINT protocol_archive_record_identities_pkey PRIMARY KEY (record_kind, record_id);


--
-- Name: protocol_archive_segments protocol_archive_segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_archive_segments
    ADD CONSTRAINT protocol_archive_segments_pkey PRIMARY KEY (id);


--
-- Name: protocol_packet_records protocol_packet_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_packet_records
    ADD CONSTRAINT protocol_packet_records_pkey PRIMARY KEY (packet_id);


--
-- Name: protocol_transfer_frame_records protocol_transfer_frame_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_transfer_frame_records
    ADD CONSTRAINT protocol_transfer_frame_records_pkey PRIMARY KEY (frame_record_id);


--
-- Name: provider_accounts provider_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_accounts
    ADD CONSTRAINT provider_accounts_pkey PRIMARY KEY (provider_account_id);


--
-- Name: provider_audit_entries provider_audit_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_audit_entries
    ADD CONSTRAINT provider_audit_entries_pkey PRIMARY KEY (provider_audit_entry_id);


--
-- Name: provider_change_approvals provider_change_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_change_approvals
    ADD CONSTRAINT provider_change_approvals_pkey PRIMARY KEY (provider_change_approval_id);


--
-- Name: provider_credentials provider_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_credentials
    ADD CONSTRAINT provider_credentials_pkey PRIMARY KEY (provider_credential_ref);


--
-- Name: provider_event_cursors provider_event_cursors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_event_cursors
    ADD CONSTRAINT provider_event_cursors_pkey PRIMARY KEY (provider_event_cursor_id);


--
-- Name: provider_event_inbox provider_event_inbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_pkey PRIMARY KEY (provider_event_inbox_id);


--
-- Name: provider_evidence provider_evidence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_evidence
    ADD CONSTRAINT provider_evidence_pkey PRIMARY KEY (provider_evidence_id);


--
-- Name: provider_reservation_changes provider_reservation_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservation_changes
    ADD CONSTRAINT provider_reservation_changes_pkey PRIMARY KEY (provider_reservation_change_id);


--
-- Name: provider_reservations provider_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_pkey PRIMARY KEY (provider_reservation_id);


--
-- Name: realized_contacts realized_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realized_contacts
    ADD CONSTRAINT realized_contacts_pkey PRIMARY KEY (realized_contact_id);


--
-- Name: replay_dispatch_decisions replay_dispatch_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_dispatch_decisions
    ADD CONSTRAINT replay_dispatch_decisions_pkey PRIMARY KEY (dispatch_decision_id);


--
-- Name: replay_dispatch_work_items replay_dispatch_work_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_dispatch_work_items
    ADD CONSTRAINT replay_dispatch_work_items_pkey PRIMARY KEY (id);


--
-- Name: replay_managed_action_requests replay_managed_action_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_action_requests
    ADD CONSTRAINT replay_managed_action_requests_pkey PRIMARY KEY (action_request_id);


--
-- Name: replay_managed_capability_records replay_managed_capability_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_capability_records
    ADD CONSTRAINT replay_managed_capability_records_pkey PRIMARY KEY (capability_record_id);


--
-- Name: replay_managed_timer_events replay_managed_timer_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_timer_events
    ADD CONSTRAINT replay_managed_timer_events_pkey PRIMARY KEY (timer_event_id);


--
-- Name: replay_runs replay_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_runs
    ADD CONSTRAINT replay_runs_pkey PRIMARY KEY (replay_run_id);


--
-- Name: replay_telemetry_samples replay_telemetry_samples_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_telemetry_samples
    ADD CONSTRAINT replay_telemetry_samples_pkey PRIMARY KEY (sample_id);


--
-- Name: scheduled_contact_revisions scheduled_contact_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_contact_revisions
    ADD CONSTRAINT scheduled_contact_revisions_pkey PRIMARY KEY (scheduled_contact_revision_id);


--
-- Name: scheduled_contacts scheduled_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_contacts
    ADD CONSTRAINT scheduled_contacts_pkey PRIMARY KEY (scheduled_contact_id);


--
-- Name: scoped_settings_revisions scoped_settings_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scoped_settings_revisions
    ADD CONSTRAINT scoped_settings_revisions_pkey PRIMARY KEY (revision_id);


--
-- Name: semantic_alarm_acknowledgements semantic_alarm_acknowledgements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_alarm_acknowledgements
    ADD CONSTRAINT semantic_alarm_acknowledgements_pkey PRIMARY KEY (acknowledgement_id);


--
-- Name: semantic_alarm_transitions semantic_alarm_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_alarm_transitions
    ADD CONSTRAINT semantic_alarm_transitions_pkey PRIMARY KEY (transition_id);


--
-- Name: semantic_latest_alarm_states semantic_latest_alarm_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_latest_alarm_states
    ADD CONSTRAINT semantic_latest_alarm_states_pkey PRIMARY KEY (id);


--
-- Name: semantic_monitoring_evaluations semantic_monitoring_evaluations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_monitoring_evaluations
    ADD CONSTRAINT semantic_monitoring_evaluations_pkey PRIMARY KEY (evaluation_id);


--
-- Name: semantic_runtime_heads semantic_runtime_heads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_runtime_heads
    ADD CONSTRAINT semantic_runtime_heads_pkey PRIMARY KEY (organization_scope_id, mission_id, partition_id);


--
-- Name: semantic_runtime_snapshots semantic_runtime_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_runtime_snapshots
    ADD CONSTRAINT semantic_runtime_snapshots_pkey PRIMARY KEY (organization_scope_id, mission_id, partition_id, runtime_basis_sha256);


--
-- Name: service_identities service_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identities
    ADD CONSTRAINT service_identities_pkey PRIMARY KEY (service_identity_id);


--
-- Name: service_identity_accountables service_identity_accountables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identity_accountables
    ADD CONSTRAINT service_identity_accountables_pkey PRIMARY KEY (accountable_id);


--
-- Name: spacecraft_application_bindings spacecraft_application_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spacecraft_application_bindings
    ADD CONSTRAINT spacecraft_application_bindings_pkey PRIMARY KEY (application_binding_id);


--
-- Name: spacecraft_config_overrides spacecraft_config_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spacecraft_config_overrides
    ADD CONSTRAINT spacecraft_config_overrides_pkey PRIMARY KEY (mission_id, spacecraft_id, path);


--
-- Name: spacecraft_configuration_revisions spacecraft_configuration_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spacecraft_configuration_revisions
    ADD CONSTRAINT spacecraft_configuration_revisions_pkey PRIMARY KEY (configuration_revision_id);


--
-- Name: staged_command_items staged_command_items_org_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_command_items
    ADD CONSTRAINT staged_command_items_org_scope_idx_uniq UNIQUE (organization_id, mission_id, staged_command_item_id);


--
-- Name: staged_command_items staged_command_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_command_items
    ADD CONSTRAINT staged_command_items_pkey PRIMARY KEY (staged_command_item_id);


--
-- Name: staged_command_items staged_command_items_scope_idx_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_command_items
    ADD CONSTRAINT staged_command_items_scope_idx_uniq UNIQUE (mission_id, staged_command_item_id);


--
-- Name: telemetry_backfill_lifecycle_events telemetry_backfill_lifecycle_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_backfill_lifecycle_events
    ADD CONSTRAINT telemetry_backfill_lifecycle_events_pkey PRIMARY KEY (backfill_lifecycle_event_id);


--
-- Name: telemetry_latest_limit_state_rebuild_runs telemetry_latest_limit_state_rebuild_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_limit_state_rebuild_runs
    ADD CONSTRAINT telemetry_latest_limit_state_rebuild_runs_pkey PRIMARY KEY (rebuild_run_id);


--
-- Name: telemetry_latest_limit_states telemetry_latest_limit_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_limit_states
    ADD CONSTRAINT telemetry_latest_limit_states_pkey PRIMARY KEY (id);


--
-- Name: telemetry_latest_value_rebuild_runs telemetry_latest_value_rebuild_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_value_rebuild_runs
    ADD CONSTRAINT telemetry_latest_value_rebuild_runs_pkey PRIMARY KEY (rebuild_run_id);


--
-- Name: telemetry_latest_values telemetry_latest_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_values
    ADD CONSTRAINT telemetry_latest_values_pkey PRIMARY KEY (id);


--
-- Name: telemetry_limit_evaluation_runs telemetry_limit_evaluation_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_limit_evaluation_runs
    ADD CONSTRAINT telemetry_limit_evaluation_runs_pkey PRIMARY KEY (limit_run_id);


--
-- Name: telemetry_limit_events telemetry_limit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_limit_events
    ADD CONSTRAINT telemetry_limit_events_pkey PRIMARY KEY (limit_event_id);


--
-- Name: telemetry_observation_identity_decision_events telemetry_observation_identity_decision_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_observation_identity_decision_events
    ADD CONSTRAINT telemetry_observation_identity_decision_events_pkey PRIMARY KEY (decision_event_id);


--
-- Name: telemetry_observation_identity_states telemetry_observation_identity_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_observation_identity_states
    ADD CONSTRAINT telemetry_observation_identity_states_pkey PRIMARY KEY (observation_identity_id);


--
-- Name: telemetry_samples telemetry_samples_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_samples
    ADD CONSTRAINT telemetry_samples_pkey PRIMARY KEY (sample_id);


--
-- Name: transport_action_requests transport_action_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_action_requests
    ADD CONSTRAINT transport_action_requests_pkey PRIMARY KEY (action_request_id);


--
-- Name: transport_capability_records transport_capability_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_capability_records
    ADD CONSTRAINT transport_capability_records_pkey PRIMARY KEY (transport_record_id);


--
-- Name: transport_timer_events transport_timer_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_timer_events
    ADD CONSTRAINT transport_timer_events_pkey PRIMARY KEY (timer_event_id);


--
-- Name: user_local_credentials user_local_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_local_credentials
    ADD CONSTRAINT user_local_credentials_pkey PRIMARY KEY (local_credential_id);


--
-- Name: user_session_tokens user_session_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_session_tokens
    ADD CONSTRAINT user_session_tokens_pkey PRIMARY KEY (session_token_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: account_events_user_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX account_events_user_id_occurred_at_index ON public.account_events USING btree (user_id, occurred_at);


--
-- Name: activation_decisions_request_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activation_decisions_request_idx ON public.activation_decisions USING btree (activation_request_id, decided_at);


--
-- Name: activation_executions_request_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX activation_executions_request_idx ON public.activation_executions USING btree (activation_request_id);


--
-- Name: activation_fleet_members_commanding_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activation_fleet_members_commanding_idx ON public.activation_fleet_members USING btree (mission_id, fleet_sha256, commanding_enabled);


--
-- Name: activation_fleet_members_sources_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activation_fleet_members_sources_idx ON public.activation_fleet_members USING gin (source_endpoint_ids);


--
-- Name: activation_requests_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX activation_requests_scope_idx ON public.activation_requests USING btree (organization_id, mission_id, requested_at);


--
-- Name: active_limit_definitions_definition_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX active_limit_definitions_definition_idx ON public.active_limit_definitions USING btree (mission_id, limit_definition_id, limit_definition_version);


--
-- Name: active_limit_definitions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX active_limit_definitions_scope_idx ON public.active_limit_definitions USING btree (organization_id, mission_id, point_id, limit_set_name);


--
-- Name: alarm_episode_events_episode_id_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alarm_episode_events_episode_id_at_index ON public.alarm_episode_events USING btree (episode_id, at);


--
-- Name: alarm_episode_events_latest_change_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alarm_episode_events_latest_change_idx ON public.alarm_episode_events USING btree (mission_id, at DESC, event_id DESC) WHERE (kind IN ('raised', 'escalated', 'deescalated', 'cleared'));


--
-- Name: alarm_episode_events_source_ref_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX alarm_episode_events_source_ref_idx ON public.alarm_episode_events USING btree (mission_id, source_ref) WHERE (source_ref IS NOT NULL);


--
-- Name: alarm_episodes_mission_id_spacecraft_id_opened_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alarm_episodes_mission_id_spacecraft_id_opened_at_index ON public.alarm_episodes USING btree (mission_id, spacecraft_id, opened_at);


--
-- Name: alarm_episodes_mission_id_state_severity_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alarm_episodes_mission_id_state_severity_index ON public.alarm_episodes USING btree (mission_id, state, severity);


--
-- Name: alarm_episodes_one_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX alarm_episodes_one_active_idx ON public.alarm_episodes USING btree (mission_id, spacecraft_scope_id, source, subject_key) WHERE ((state)::text = 'active'::text);


--
-- Name: application_dispatch_decisions_evidence_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX application_dispatch_decisions_evidence_id_index ON public.application_dispatch_decisions USING btree (evidence_id);


--
-- Name: application_dispatch_decisions_packet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX application_dispatch_decisions_packet_id_index ON public.application_dispatch_decisions USING btree (packet_id);


--
-- Name: application_dispatch_work_items_dispatch_decision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX application_dispatch_work_items_dispatch_decision_id_index ON public.application_dispatch_work_items USING btree (dispatch_decision_id);


--
-- Name: application_installation_events_installation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX application_installation_events_installation_idx ON public.application_installation_events USING btree (application_installation_id, occurred_at);


--
-- Name: application_installations_host_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX application_installations_host_scope_idx ON public.application_installations USING btree (organization_id, mission_id, scope_kind, scope_id);


--
-- Name: application_installations_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX application_installations_scope_idx ON public.application_installations USING btree (organization_id, mission_id, scope_kind, scope_id, application_key);


--
-- Name: application_packet_binding_configurations_input_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX application_packet_binding_configurations_input_idx ON public.application_packet_binding_configurations USING btree (application_installation_id, input_id, input_version);


--
-- Name: application_packet_binding_configurations_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX application_packet_binding_configurations_mission_idx ON public.application_packet_binding_configurations USING btree (organization_id, mission_id);


--
-- Name: application_packet_binding_resources_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX application_packet_binding_resources_identity_idx ON public.application_packet_binding_resources USING btree (packet_binding_id, resource_id);


--
-- Name: application_packet_bindings_configuration_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX application_packet_bindings_configuration_idx ON public.application_packet_bindings USING btree (packet_binding_configuration_id);


--
-- Name: automation_grant_decisions_grant_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX automation_grant_decisions_grant_index ON public.automation_grant_decisions USING btree (organization_id, mission_id, automation_grant_id);


--
-- Name: automation_grant_operations_scope_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX automation_grant_operations_scope_index ON public.automation_grant_operations USING btree (organization_id, mission_id, operation_id);


--
-- Name: automation_grants_mission_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX automation_grants_mission_state_idx ON public.automation_grants USING btree (organization_id, mission_id, lifecycle_state, valid_until);


--
-- Name: automation_grants_one_active_per_service_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX automation_grants_one_active_per_service_idx ON public.automation_grants USING btree (organization_id, mission_id, service_identity_id) WHERE (lifecycle_state IN ('active', 'suspended'));


--
-- Name: automation_grants_replaces_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX automation_grants_replaces_index ON public.automation_grants USING btree (organization_id, mission_id, replaces_grant_id);


--
-- Name: automation_grants_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX automation_grants_state_index ON public.automation_grants USING btree (organization_id, mission_id, lifecycle_state);


--
-- Name: background_jobs_job_type_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX background_jobs_job_type_run_id_index ON public.background_jobs USING btree (job_type, run_id);


--
-- Name: background_jobs_mission_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX background_jobs_mission_id_inserted_at_index ON public.background_jobs USING btree (mission_id, inserted_at);


--
-- Name: background_jobs_status_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX background_jobs_status_inserted_at_index ON public.background_jobs USING btree (status, inserted_at);


--
-- Name: booking_resolutions_conflicts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX booking_resolutions_conflicts_idx ON public.booking_resolutions USING btree (organization_id, mission_id, starts_at) WHERE (conflict_state IN ('open', 'acknowledged'));


--
-- Name: booking_resolutions_contact_plan_execution_item_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX booking_resolutions_contact_plan_execution_item_id_index ON public.booking_resolutions USING btree (contact_plan_execution_item_id);


--
-- Name: booking_resolutions_organization_id_mission_id_provider_reserva; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX booking_resolutions_organization_id_mission_id_provider_reserva ON public.booking_resolutions USING btree (organization_id, mission_id, provider_reservation_id);


--
-- Name: catalog_artifacts_mission_id_catalog_database_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_artifacts_mission_id_catalog_database_id_index ON public.catalog_artifacts USING btree (mission_id, catalog_database_id);


--
-- Name: catalog_artifacts_mission_id_catalog_family_uploaded_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_artifacts_mission_id_catalog_family_uploaded_at_index ON public.catalog_artifacts USING btree (mission_id, catalog_family, uploaded_at);


--
-- Name: catalog_artifacts_mission_id_content_sha256_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_artifacts_mission_id_content_sha256_index ON public.catalog_artifacts USING btree (mission_id, content_sha256);


--
-- Name: catalog_artifacts_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_artifacts_organization_id_mission_id_index ON public.catalog_artifacts USING btree (organization_id, mission_id);


--
-- Name: catalog_databases_mission_slug_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX catalog_databases_mission_slug_idx ON public.catalog_databases USING btree (organization_id, mission_id, slug);


--
-- Name: catalog_databases_organization_id_mission_id_catalog_family_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_databases_organization_id_mission_id_catalog_family_ind ON public.catalog_databases USING btree (organization_id, mission_id, catalog_family);


--
-- Name: catalog_databases_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_databases_organization_id_mission_id_index ON public.catalog_databases USING btree (organization_id, mission_id);


--
-- Name: catalog_import_runs_mission_id_artifact_id_started_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_import_runs_mission_id_artifact_id_started_at_index ON public.catalog_import_runs USING btree (mission_id, artifact_id, started_at);


--
-- Name: catalog_import_runs_mission_id_catalog_database_id_started_at_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_import_runs_mission_id_catalog_database_id_started_at_i ON public.catalog_import_runs USING btree (mission_id, catalog_database_id, started_at);


--
-- Name: catalog_import_runs_mission_id_importer_key_started_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_import_runs_mission_id_importer_key_started_at_index ON public.catalog_import_runs USING btree (mission_id, importer_key, started_at);


--
-- Name: catalog_import_runs_mission_id_status_started_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_import_runs_mission_id_status_started_at_index ON public.catalog_import_runs USING btree (mission_id, status, started_at);


--
-- Name: catalog_import_runs_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_import_runs_organization_id_mission_id_index ON public.catalog_import_runs USING btree (organization_id, mission_id);


--
-- Name: catalog_revisions_artifact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_revisions_artifact_id_index ON public.catalog_revisions USING btree (artifact_id);


--
-- Name: catalog_revisions_database_label_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX catalog_revisions_database_label_idx ON public.catalog_revisions USING btree (catalog_database_id, revision_label);


--
-- Name: catalog_revisions_database_number_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX catalog_revisions_database_number_idx ON public.catalog_revisions USING btree (catalog_database_id, revision_number);


--
-- Name: catalog_revisions_import_run_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX catalog_revisions_import_run_idx ON public.catalog_revisions USING btree (import_run_id);


--
-- Name: catalog_revisions_mission_model_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_revisions_mission_model_revision_id_index ON public.catalog_revisions USING btree (mission_model_revision_id);


--
-- Name: catalog_revisions_organization_id_mission_id_catalog_database_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX catalog_revisions_organization_id_mission_id_catalog_database_i ON public.catalog_revisions USING btree (organization_id, mission_id, catalog_database_id);


--
-- Name: combined_downlink_records_mission_id_realized_contact_id_observ; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX combined_downlink_records_mission_id_realized_contact_id_observ ON public.combined_downlink_records USING btree (mission_id, realized_contact_id, observation_key);


--
-- Name: command_approvals_organization_id_decided_at_DESC_command_appro; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "command_approvals_organization_id_decided_at_DESC_command_appro" ON public.command_approvals USING btree (organization_id, decided_at DESC, command_approval_id DESC);


--
-- Name: command_approvals_organization_id_mission_id_command_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_approvals_organization_id_mission_id_command_request_id ON public.command_approvals USING btree (organization_id, mission_id, command_request_id, decided_at);


--
-- Name: command_drafts_owner_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_drafts_owner_index ON public.command_drafts USING btree (organization_id, mission_id, user_id);


--
-- Name: command_group_events_command_group_id_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_group_events_command_group_id_at_index ON public.command_group_events USING btree (command_group_id, at);


--
-- Name: command_groups_mission_id_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_groups_mission_id_state_index ON public.command_groups USING btree (mission_id, state);


--
-- Name: command_groups_operation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_groups_operation_idx ON public.command_groups USING btree (mission_id, operation_id) WHERE (operation_id IS NOT NULL);


--
-- Name: command_queue_entries_active_release_attempt_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_queue_entries_active_release_attempt_id_index ON public.command_queue_entries USING btree (active_release_attempt_id) WHERE (active_release_attempt_id IS NOT NULL);


--
-- Name: command_queue_entries_lane_sequence_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_queue_entries_lane_sequence_idx ON public.command_queue_entries USING btree (organization_id, mission_id, queue_lane_key, queue_sequence);


--
-- Name: command_queue_entries_organization_id_mission_id_queue_lane_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_queue_entries_organization_id_mission_id_queue_lane_key ON public.command_queue_entries USING btree (organization_id, mission_id, queue_lane_key, lifecycle_state, priority, queue_sequence);


--
-- Name: command_queue_entries_organization_id_mission_id_source_endpoin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_queue_entries_organization_id_mission_id_source_endpoin ON public.command_queue_entries USING btree (organization_id, mission_id, source_endpoint_ref);


--
-- Name: command_release_attempts_contact_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_release_attempts_contact_org_scope_idx ON public.command_release_attempts USING btree (organization_id, mission_id, realized_contact_id);


--
-- Name: command_release_attempts_queue_entry_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_release_attempts_queue_entry_org_scope_idx ON public.command_release_attempts USING btree (organization_id, mission_id, command_queue_entry_id);


--
-- Name: command_release_attempts_request_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_release_attempts_request_org_scope_idx ON public.command_release_attempts USING btree (organization_id, mission_id, command_request_id);


--
-- Name: command_release_attempts_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_release_attempts_scope_idx ON public.command_release_attempts USING btree (mission_id, command_release_attempt_id);


--
-- Name: command_requests_group_member_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_requests_group_member_idx ON public.command_requests USING btree (command_group_id, group_target_index, group_position) WHERE (command_group_id IS NOT NULL);


--
-- Name: command_requests_organization_id_mission_id_requested_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_requests_organization_id_mission_id_requested_at_index ON public.command_requests USING btree (organization_id, mission_id, requested_at);


--
-- Name: command_requests_organization_id_mission_id_source_command_stag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_requests_organization_id_mission_id_source_command_stag ON public.command_requests USING btree (organization_id, mission_id, source_command_stage_id);


--
-- Name: command_requests_organization_id_mission_id_source_endpoint_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_requests_organization_id_mission_id_source_endpoint_ref ON public.command_requests USING btree (organization_id, mission_id, source_endpoint_ref);


--
-- Name: command_stages_organization_id_mission_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_stages_organization_id_mission_id_inserted_at_index ON public.command_stages USING btree (organization_id, mission_id, inserted_at);


--
-- Name: command_verifier_instances_lane_state_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_verifier_instances_lane_state_org_scope_idx ON public.command_verifier_instances USING btree (organization_id, mission_id, source_endpoint_ref, lifecycle_state);


--
-- Name: command_verifier_instances_release_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_verifier_instances_release_org_scope_idx ON public.command_verifier_instances USING btree (organization_id, mission_id, command_release_attempt_id);


--
-- Name: command_verifier_instances_request_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_verifier_instances_request_org_scope_idx ON public.command_verifier_instances USING btree (organization_id, mission_id, command_request_id);


--
-- Name: command_verifier_instances_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX command_verifier_instances_scope_idx ON public.command_verifier_instances USING btree (mission_id, command_verifier_instance_id);


--
-- Name: command_verifier_instances_timeout_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX command_verifier_instances_timeout_org_scope_idx ON public.command_verifier_instances USING btree (organization_id, mission_id, lifecycle_state, timeout_at);


--
-- Name: comms_ground_stations_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX comms_ground_stations_code_idx ON public.comms_ground_stations USING btree (mission_id, code) WHERE ((code IS NOT NULL) AND ((lifecycle_state)::text = 'active'::text));


--
-- Name: comms_ground_stations_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_ground_stations_org_mission_idx ON public.comms_ground_stations USING btree (organization_id, mission_id);


--
-- Name: comms_ground_stations_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX comms_ground_stations_scope_idx ON public.comms_ground_stations USING btree (mission_id, ground_station_id);


--
-- Name: comms_routing_rule_events_rule_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_routing_rule_events_rule_idx ON public.comms_routing_rule_events USING btree (organization_id, mission_id, routing_rule_id);


--
-- Name: comms_routing_rules_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_routing_rules_org_mission_idx ON public.comms_routing_rules USING btree (organization_id, mission_id);


--
-- Name: comms_routing_rules_profile_route_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX comms_routing_rules_profile_route_idx ON public.comms_routing_rules USING btree (mission_id, spacecraft_id, profile_rule_id, ground_station_id, leg_direction) WHERE ((origin)::text = 'profile'::text);


--
-- Name: comms_routing_rules_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX comms_routing_rules_scope_idx ON public.comms_routing_rules USING btree (mission_id, routing_rule_id);


--
-- Name: comms_routing_rules_spacecraft_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_routing_rules_spacecraft_idx ON public.comms_routing_rules USING btree (organization_id, mission_id, spacecraft_id);


--
-- Name: comms_routing_rules_transport_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_routing_rules_transport_idx ON public.comms_routing_rules USING btree (organization_id, mission_id, transport_id);


--
-- Name: comms_transports_mission_provider_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_transports_mission_provider_idx ON public.comms_transports USING btree (mission_id, mission_provider_id, mission_provider_version);


--
-- Name: comms_transports_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_transports_org_mission_idx ON public.comms_transports USING btree (organization_id, mission_id);


--
-- Name: comms_transports_provider_profile_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comms_transports_provider_profile_idx ON public.comms_transports USING btree (mission_id, materialized_provider_profile_id);


--
-- Name: comms_transports_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX comms_transports_scope_idx ON public.comms_transports USING btree (mission_id, transport_id, version);


--
-- Name: contact_actions_mission_id_action_kind_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_actions_mission_id_action_kind_index ON public.contact_actions USING btree (mission_id, action_kind);


--
-- Name: contact_actions_mission_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_actions_mission_id_occurred_at_index ON public.contact_actions USING btree (mission_id, occurred_at);


--
-- Name: contact_actions_mission_id_realized_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_actions_mission_id_realized_contact_id_index ON public.contact_actions USING btree (mission_id, realized_contact_id);


--
-- Name: contact_actions_mission_id_scheduled_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_actions_mission_id_scheduled_contact_id_index ON public.contact_actions USING btree (mission_id, scheduled_contact_id);


--
-- Name: contact_actions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_actions_scope_idx ON public.contact_actions USING btree (mission_id, contact_action_id);


--
-- Name: contact_link_assignments_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_link_assignments_organization_id_mission_id_index ON public.contact_link_assignments USING btree (organization_id, mission_id);


--
-- Name: contact_link_assignments_organization_id_mission_id_path_templa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_link_assignments_organization_id_mission_id_path_templa ON public.contact_link_assignments USING btree (organization_id, mission_id, path_template_id);


--
-- Name: contact_link_assignments_organization_id_mission_id_source_endp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_link_assignments_organization_id_mission_id_source_endp ON public.contact_link_assignments USING btree (organization_id, mission_id, source_endpoint_ref);


--
-- Name: contact_link_assignments_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_link_assignments_scope_idx ON public.contact_link_assignments USING btree (mission_id, link_assignment_id);


--
-- Name: contact_opportunity_snapshots_contact_planning_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_opportunity_snapshots_contact_planning_run_id_index ON public.contact_opportunity_snapshots USING btree (contact_planning_run_id);


--
-- Name: contact_opportunity_snapshots_content_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_opportunity_snapshots_content_idx ON public.contact_opportunity_snapshots USING btree (contact_planning_search_id, provider_opportunity_ref, content_sha256);


--
-- Name: contact_opportunity_snapshots_requirement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_opportunity_snapshots_requirement_idx ON public.contact_opportunity_snapshots USING btree (organization_id, mission_id, contact_requirement_id, starts_at);


--
-- Name: contact_pass_results_organization_id_mission_id_contact_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_pass_results_organization_id_mission_id_contact_plan_id ON public.contact_pass_results USING btree (organization_id, mission_id, contact_plan_id);


--
-- Name: contact_pass_results_organization_id_mission_id_ground_station_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_pass_results_organization_id_mission_id_ground_station_ ON public.contact_pass_results USING btree (organization_id, mission_id, ground_station_ref, planned_aos);


--
-- Name: contact_pass_results_organization_id_mission_id_planned_aos_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_pass_results_organization_id_mission_id_planned_aos_ind ON public.contact_pass_results USING btree (organization_id, mission_id, planned_aos);


--
-- Name: contact_pass_results_organization_id_provider_id_closed_at_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_pass_results_organization_id_provider_id_closed_at_inde ON public.contact_pass_results USING btree (organization_id, provider_id, closed_at);


--
-- Name: contact_path_templates_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_path_templates_organization_id_mission_id_index ON public.contact_path_templates USING btree (organization_id, mission_id);


--
-- Name: contact_path_templates_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_path_templates_scope_idx ON public.contact_path_templates USING btree (mission_id, path_template_id, version);


--
-- Name: contact_plan_approvals_version_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_approvals_version_idx ON public.contact_plan_approvals USING btree (contact_plan_id, contact_plan_version);


--
-- Name: contact_plan_execution_items_idempotency_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_execution_items_idempotency_idx ON public.contact_plan_execution_items USING btree (mission_id, idempotency_key);


--
-- Name: contact_plan_execution_items_selection_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_execution_items_selection_idx ON public.contact_plan_execution_items USING btree (contact_plan_id, contact_plan_version, contact_opportunity_snapshot_id);


--
-- Name: contact_plan_execution_items_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_plan_execution_items_state_idx ON public.contact_plan_execution_items USING btree (organization_id, mission_id, lifecycle_state, updated_at);


--
-- Name: contact_plan_operations_scope_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_operations_scope_index ON public.contact_plan_operations USING btree (organization_id, mission_id, operation_id);


--
-- Name: contact_plan_opportunity_refs_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_opportunity_refs_identity_idx ON public.contact_plan_opportunity_refs USING btree (contact_plan_id, contact_plan_version, contact_opportunity_snapshot_id);


--
-- Name: contact_plan_requirement_refs_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_requirement_refs_identity_idx ON public.contact_plan_requirement_refs USING btree (contact_plan_id, contact_plan_version, contact_requirement_id);


--
-- Name: contact_plan_run_refs_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_run_refs_identity_idx ON public.contact_plan_run_refs USING btree (contact_plan_id, contact_plan_version, contact_planning_run_id);


--
-- Name: contact_plan_submissions_round_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plan_submissions_round_index ON public.contact_plan_submissions USING btree (organization_id, mission_id, contact_plan_id, round);


--
-- Name: contact_planning_runs_requirement_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_planning_runs_requirement_idx ON public.contact_planning_runs USING btree (organization_id, mission_id, contact_requirement_id, started_at);


--
-- Name: contact_planning_searches_mission_outcome_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_planning_searches_mission_outcome_idx ON public.contact_planning_searches USING btree (organization_id, mission_id, outcome);


--
-- Name: contact_planning_searches_route_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_planning_searches_route_idx ON public.contact_planning_searches USING btree (contact_planning_run_id, route_key);


--
-- Name: contact_plans_mission_operation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_plans_mission_operation_id_index ON public.contact_plans USING btree (mission_id, operation_id) WHERE (operation_id IS NOT NULL);


--
-- Name: contact_plans_mission_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_plans_mission_state_idx ON public.contact_plans USING btree (organization_id, mission_id, lifecycle_state);


--
-- Name: contact_provider_profiles_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_provider_profiles_organization_id_mission_id_index ON public.contact_provider_profiles USING btree (organization_id, mission_id);


--
-- Name: contact_provider_profiles_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_provider_profiles_scope_idx ON public.contact_provider_profiles USING btree (mission_id, provider_profile_id, version);


--
-- Name: contact_requirement_occurrences_horizon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirement_occurrences_horizon_idx ON public.contact_requirement_occurrences USING btree (organization_id, mission_id, occurrence_at, generation_state);


--
-- Name: contact_requirement_occurrences_spacecraft_identity_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_requirement_occurrences_spacecraft_identity_uniq ON public.contact_requirement_occurrences USING btree (organization_id, mission_id, contact_requirement_template_id, contact_requirement_template_version, occurrence_at, spacecraft_id);


--
-- Name: contact_requirement_template_versions_spacecraft_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirement_template_versions_spacecraft_idx ON public.contact_requirement_template_versions USING btree (organization_id, mission_id, spacecraft_id) WHERE (spacecraft_id IS NOT NULL);


--
-- Name: contact_requirement_templates_mission_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirement_templates_mission_state_idx ON public.contact_requirement_templates USING btree (organization_id, mission_id, lifecycle_state);


--
-- Name: contact_requirement_versions_mission_horizon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirement_versions_mission_horizon_idx ON public.contact_requirement_versions USING btree (organization_id, mission_id, earliest_start, latest_end) WHERE (earliest_start IS NOT NULL);


--
-- Name: contact_requirement_versions_requirement_version_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirement_versions_requirement_version_idx ON public.contact_requirement_versions USING btree (contact_requirement_id, version);


--
-- Name: contact_requirement_versions_spacecraft_horizon_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirement_versions_spacecraft_horizon_idx ON public.contact_requirement_versions USING btree (spacecraft_id, organization_id, mission_id, earliest_start, latest_end);


--
-- Name: contact_requirements_active_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirements_active_mission_idx ON public.contact_requirements USING btree (organization_id, mission_id) WHERE ((lifecycle_state)::text = 'active'::text);


--
-- Name: contact_requirements_inactive_mission_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_requirements_inactive_mission_state_idx ON public.contact_requirements USING btree (organization_id, mission_id, lifecycle_state) WHERE ((lifecycle_state)::text <> 'active'::text);


--
-- Name: contact_schedule_operations_organization_id_user_id_mission_id_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_schedule_operations_organization_id_user_id_mission_id_ ON public.contact_schedule_operations USING btree (organization_id, user_id, mission_id, inserted_at);


--
-- Name: contact_schedule_unresolved_reservation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_schedule_unresolved_reservation ON public.contact_schedule_operations USING btree (organization_id, mission_id, reservation_id) WHERE (status IN ('accepted', 'unconfirmed'));


--
-- Name: contact_transport_profiles_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contact_transport_profiles_organization_id_mission_id_index ON public.contact_transport_profiles USING btree (organization_id, mission_id);


--
-- Name: contact_transport_profiles_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_transport_profiles_scope_idx ON public.contact_transport_profiles USING btree (mission_id, transport_profile_id, version);


--
-- Name: dashboard_deployments_scope_dashboard_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_deployments_scope_dashboard_idx ON public.dashboard_deployments USING btree (organization_id, mission_id, dashboard_id);


--
-- Name: dashboard_investigation_presets_dashboard_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_investigation_presets_dashboard_idx ON public.dashboard_investigation_presets USING btree (organization_id, mission_id, dashboard_id, inserted_at);


--
-- Name: dashboard_investigation_presets_dashboard_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_investigation_presets_dashboard_name_idx ON public.dashboard_investigation_presets USING btree (organization_id, mission_id, dashboard_id, name);


--
-- Name: dashboard_investigation_presets_kind_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_investigation_presets_kind_idx ON public.dashboard_investigation_presets USING btree (organization_id, mission_id, preset_kind);


--
-- Name: dashboard_library_items_scope_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_library_items_scope_name_idx ON public.dashboard_library_items USING btree (organization_id, mission_id, name);


--
-- Name: dashboard_library_versions_item_version_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_library_versions_item_version_idx ON public.dashboard_library_versions USING btree (dashboard_library_item_id, version);


--
-- Name: dashboard_lifecycle_events_dashboard_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_lifecycle_events_dashboard_idx ON public.dashboard_lifecycle_events USING btree (organization_id, mission_id, dashboard_id);


--
-- Name: dashboard_lifecycle_events_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_lifecycle_events_type_idx ON public.dashboard_lifecycle_events USING btree (organization_id, mission_id, event_type);


--
-- Name: dashboard_playlists_scope_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_playlists_scope_name_idx ON public.dashboard_playlists USING btree (organization_id, mission_id, name);


--
-- Name: dashboard_runtime_invalidation_decisions_dashboard_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_runtime_invalidation_decisions_dashboard_idx ON public.dashboard_runtime_invalidation_decision_events USING btree (organization_id, mission_id, dashboard_id, decision_observed_at);


--
-- Name: dashboard_runtime_invalidation_decisions_invalidation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_runtime_invalidation_decisions_invalidation_idx ON public.dashboard_runtime_invalidation_decision_events USING btree (invalidation_event_id);


--
-- Name: dashboard_runtime_invalidation_decisions_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_runtime_invalidation_decisions_status_idx ON public.dashboard_runtime_invalidation_decision_events USING btree (organization_id, mission_id, decision_status);


--
-- Name: dashboard_shares_organization_id_mission_id_dashboard_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_shares_organization_id_mission_id_dashboard_id_index ON public.dashboard_shares USING btree (organization_id, mission_id, dashboard_id);


--
-- Name: dashboard_snapshots_scope_dashboard_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_snapshots_scope_dashboard_idx ON public.dashboard_snapshots USING btree (organization_id, mission_id, dashboard_id);


--
-- Name: dashboard_user_preferences_navigation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_user_preferences_navigation_idx ON public.dashboard_user_preferences USING btree (organization_id, mission_id, user_id, starred, last_viewed_at);


--
-- Name: dashboard_user_preferences_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_user_preferences_scope_idx ON public.dashboard_user_preferences USING btree (organization_id, mission_id, user_id, dashboard_id);


--
-- Name: dashboard_versions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dashboard_versions_scope_idx ON public.dashboard_versions USING btree (organization_id, mission_id, dashboard_id);


--
-- Name: dashboard_versions_scope_version_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dashboard_versions_scope_version_idx ON public.dashboard_versions USING btree (organization_id, mission_id, dashboard_id, version);


--
-- Name: data_source_binding_events_binding_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_binding_events_binding_time_idx ON public.data_source_binding_events USING btree (binding_id, occurred_at);


--
-- Name: data_source_binding_events_current_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_binding_events_current_source_idx ON public.data_source_binding_events USING btree (current_data_source_id);


--
-- Name: data_source_binding_events_scope_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_binding_events_scope_type_idx ON public.data_source_binding_events USING btree (organization_id, mission_id, event_type);


--
-- Name: data_source_bindings_data_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_bindings_data_source_idx ON public.data_source_bindings USING btree (data_source_id);


--
-- Name: data_source_bindings_resolution_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_bindings_resolution_idx ON public.data_source_bindings USING btree (organization_id, mission_id, realm, logical_source);


--
-- Name: data_source_bindings_status_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_bindings_status_scope_idx ON public.data_source_bindings USING btree (status, organization_id, mission_id);


--
-- Name: data_source_credential_events_ref_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_credential_events_ref_time_idx ON public.data_source_credential_events USING btree (credentials_ref, occurred_at);


--
-- Name: data_source_credential_events_scope_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_credential_events_scope_type_idx ON public.data_source_credential_events USING btree (organization_id, mission_id, event_type);


--
-- Name: data_source_credentials_data_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_credentials_data_source_idx ON public.data_source_credential_references USING btree (data_source_id);


--
-- Name: data_source_credentials_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_credentials_scope_idx ON public.data_source_credential_references USING btree (organization_id, mission_id);


--
-- Name: data_source_definition_events_scope_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_definition_events_scope_type_idx ON public.data_source_definition_events USING btree (organization_id, mission_id, event_type);


--
-- Name: data_source_definition_events_source_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_definition_events_source_time_idx ON public.data_source_definition_events USING btree (data_source_id, occurred_at);


--
-- Name: data_source_definitions_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_definitions_org_mission_idx ON public.data_source_definitions USING btree (organization_id, mission_id);


--
-- Name: data_source_definitions_status_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_definitions_status_scope_idx ON public.data_source_definitions USING btree (status, organization_id, mission_id);


--
-- Name: data_source_health_events_data_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_events_data_source_idx ON public.data_source_health_events USING btree (data_source_id);


--
-- Name: data_source_health_events_key_observed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_events_key_observed_idx ON public.data_source_health_events USING btree (source_health_key, observed_at);


--
-- Name: data_source_health_events_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_events_replay_idx ON public.data_source_health_events USING btree (organization_id, mission_id, replay_run_id);


--
-- Name: data_source_health_events_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_events_scope_idx ON public.data_source_health_events USING btree (organization_id, mission_id, logical_source);


--
-- Name: data_source_health_statuses_data_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_statuses_data_source_idx ON public.data_source_health_statuses USING btree (data_source_id);


--
-- Name: data_source_health_statuses_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_statuses_replay_idx ON public.data_source_health_statuses USING btree (organization_id, mission_id, replay_run_id);


--
-- Name: data_source_health_statuses_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_health_statuses_scope_idx ON public.data_source_health_statuses USING btree (organization_id, mission_id, logical_source);


--
-- Name: data_source_watermark_events_data_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_events_data_source_idx ON public.data_source_watermark_events USING btree (data_source_id);


--
-- Name: data_source_watermark_events_key_observed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_events_key_observed_idx ON public.data_source_watermark_events USING btree (source_watermark_key, observed_at);


--
-- Name: data_source_watermark_events_observed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_events_observed_idx ON public.data_source_watermark_events USING btree (observed_at);


--
-- Name: data_source_watermark_events_replay_run_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_events_replay_run_idx ON public.data_source_watermark_events USING btree (mission_id, replay_run_id);


--
-- Name: data_source_watermark_events_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_events_scope_idx ON public.data_source_watermark_events USING btree (organization_id, mission_id, logical_source);


--
-- Name: data_source_watermark_statuses_data_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_statuses_data_source_idx ON public.data_source_watermark_statuses USING btree (data_source_id);


--
-- Name: data_source_watermark_statuses_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_statuses_event_idx ON public.data_source_watermark_statuses USING btree (source_watermark_event_id);


--
-- Name: data_source_watermark_statuses_replay_run_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_statuses_replay_run_idx ON public.data_source_watermark_statuses USING btree (mission_id, replay_run_id);


--
-- Name: data_source_watermark_statuses_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_source_watermark_statuses_scope_idx ON public.data_source_watermark_statuses USING btree (organization_id, mission_id, logical_source);


--
-- Name: derived_telemetry_evaluation_runs_mission_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX derived_telemetry_evaluation_runs_mission_id_inserted_at_index ON public.derived_telemetry_evaluation_runs USING btree (mission_id, inserted_at);


--
-- Name: derived_telemetry_latest_value_rebuild_runs_mission_id_inserted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX derived_telemetry_latest_value_rebuild_runs_mission_id_inserted ON public.derived_telemetry_latest_value_rebuild_runs USING btree (mission_id, inserted_at);


--
-- Name: derived_telemetry_latest_values_mission_id_point_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX derived_telemetry_latest_values_mission_id_point_name_index ON public.derived_telemetry_latest_values USING btree (mission_id, point_name);


--
-- Name: derived_telemetry_latest_values_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX derived_telemetry_latest_values_scope_idx ON public.derived_telemetry_latest_values USING btree (mission_id, spacecraft_scope_id, point_id);


--
-- Name: derived_telemetry_samples_mission_id_point_id_receipt_time_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX derived_telemetry_samples_mission_id_point_id_receipt_time_inde ON public.derived_telemetry_samples USING btree (mission_id, point_id, receipt_time);


--
-- Name: derived_telemetry_samples_mission_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX derived_telemetry_samples_mission_id_receipt_time_index ON public.derived_telemetry_samples USING btree (mission_id, receipt_time);


--
-- Name: derived_telemetry_samples_trigger_sample_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX derived_telemetry_samples_trigger_sample_id_index ON public.derived_telemetry_samples USING btree (trigger_sample_id);


--
-- Name: downlink_diagnostics_mission_id_realized_contact_id_observation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downlink_diagnostics_mission_id_realized_contact_id_observation ON public.downlink_diagnostics USING btree (mission_id, realized_contact_id, observation_key);


--
-- Name: downlink_diagnostics_mission_id_realized_contact_id_path_id_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downlink_diagnostics_mission_id_realized_contact_id_path_id_ind ON public.downlink_diagnostics USING btree (mission_id, realized_contact_id, path_id);


--
-- Name: downlink_observations_mission_id_realized_contact_id_observatio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downlink_observations_mission_id_realized_contact_id_observatio ON public.downlink_observations USING btree (mission_id, realized_contact_id, observation_key);


--
-- Name: downlink_observations_mission_id_realized_contact_id_path_id_in; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX downlink_observations_mission_id_realized_contact_id_path_id_in ON public.downlink_observations USING btree (mission_id, realized_contact_id, path_id);


--
-- Name: faaid_logical_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX faaid_logical_identity_idx ON public.federated_application_action_idempotencies USING btree (organization_id, actor_kind, actor_id, idempotency_key_digest);


--
-- Name: federated_application_action_idempotencies_generation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX federated_application_action_idempotencies_generation_id_index ON public.federated_application_action_idempotencies USING btree (generation_id);


--
-- Name: federated_application_action_idempotencies_retention_reference_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX federated_application_action_idempotencies_retention_reference_ ON public.federated_application_action_idempotencies USING btree (retention_reference);


--
-- Name: fleet_automation_actions_idempotency_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fleet_automation_actions_idempotency_idx ON public.fleet_automation_actions USING btree (idempotency_key);


--
-- Name: fleet_automation_actions_run_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fleet_automation_actions_run_idx ON public.fleet_automation_actions USING btree (organization_id, mission_id, fleet_planning_run_id, action);


--
-- Name: fleet_planning_decisions_review_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fleet_planning_decisions_review_idx ON public.fleet_planning_decisions USING btree (organization_id, mission_id, disposition, score);


--
-- Name: fleet_planning_decisions_snapshot_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fleet_planning_decisions_snapshot_uniq ON public.fleet_planning_decisions USING btree (fleet_planning_run_id, contact_opportunity_snapshot_id);


--
-- Name: fleet_planning_policies_mission_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fleet_planning_policies_mission_uniq ON public.fleet_planning_policies USING btree (organization_id, mission_id);


--
-- Name: fleet_planning_policy_approvals_version_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fleet_planning_policy_approvals_version_uniq ON public.fleet_planning_policy_approvals USING btree (organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version);


--
-- Name: fleet_planning_run_requirement_refs_input_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fleet_planning_run_requirement_refs_input_uniq ON public.fleet_planning_run_requirement_refs USING btree (fleet_planning_run_id, contact_requirement_id, contact_requirement_version);


--
-- Name: fleet_planning_run_requirement_refs_progress_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fleet_planning_run_requirement_refs_progress_idx ON public.fleet_planning_run_requirement_refs USING btree (organization_id, mission_id, input_state, result_state);


--
-- Name: fleet_planning_runs_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fleet_planning_runs_mission_idx ON public.fleet_planning_runs USING btree (organization_id, mission_id, inserted_at);


--
-- Name: fleet_planning_runs_mission_operation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX fleet_planning_runs_mission_operation_id_index ON public.fleet_planning_runs USING btree (mission_id, operation_id) WHERE (operation_id IS NOT NULL);


--
-- Name: fleet_planning_runs_progress_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX fleet_planning_runs_progress_idx ON public.fleet_planning_runs USING btree (organization_id, mission_id, lifecycle_state, phase);


--
-- Name: frar_catalog_publication_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frar_catalog_publication_idx ON public.frontend_release_activation_requests USING btree (catalog_publication_id);


--
-- Name: frar_generation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frar_generation_idx ON public.frontend_release_activation_requests USING btree (generation_id);


--
-- Name: frar_idempotency_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frar_idempotency_key_idx ON public.frontend_release_activation_requests USING btree (idempotency_key_digest);


--
-- Name: frcb_generation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX frcb_generation_idx ON public.frontend_release_catalog_bindings USING btree (generation_id);


--
-- Name: frcg_catalog_publication_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frcg_catalog_publication_idx ON public.frontend_release_catalog_generations USING btree (catalog_publication_id);


--
-- Name: frcg_sequence_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frcg_sequence_idx ON public.frontend_release_catalog_generations USING btree (sequence);


--
-- Name: frcp_catalog_digest_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frcp_catalog_digest_idx ON public.frontend_release_catalog_publications USING btree (catalog_digest);


--
-- Name: frcp_sequence_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frcp_sequence_idx ON public.frontend_release_catalog_publications USING btree (sequence);


--
-- Name: frcp_signed_document_digest_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frcp_signed_document_digest_idx ON public.frontend_release_catalog_publications USING btree (signed_document_digest);


--
-- Name: frontend_release_artifacts_publication_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_artifacts_publication_path_idx ON public.frontend_release_artifacts USING btree (release_publication_id, path);


--
-- Name: frontend_release_object_chunks_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_object_chunks_pkey ON public.frontend_release_object_chunks USING btree (sha256, chunk_index);


--
-- Name: frontend_release_publications_payload_digest_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_publications_payload_digest_idx ON public.frontend_release_publications USING btree (payload_digest);


--
-- Name: frontend_release_publications_publication_release_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_publications_publication_release_idx ON public.frontend_release_publications USING btree (publication_id, release_id);


--
-- Name: frontend_release_publications_release_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_publications_release_idx ON public.frontend_release_publications USING btree (release_id);


--
-- Name: frontend_release_publications_signed_document_digest_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_publications_signed_document_digest_idx ON public.frontend_release_publications USING btree (signed_document_digest);


--
-- Name: frontend_release_staged_object_chunks_pkey; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX frontend_release_staged_object_chunks_pkey ON public.frontend_release_staged_object_chunks USING btree (sha256, chunk_index);


--
-- Name: frontend_release_staged_objects_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX frontend_release_staged_objects_expiry_idx ON public.frontend_release_staged_objects USING btree (expires_at);


--
-- Name: governed_binding_rules_binding_set_row_id_priority_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX governed_binding_rules_binding_set_row_id_priority_index ON public.governed_binding_rules USING btree (binding_set_row_id, priority);


--
-- Name: governed_binding_rules_binding_set_rule_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_binding_rules_binding_set_rule_idx ON public.governed_binding_rules USING btree (binding_set_row_id, binding_rule_id);


--
-- Name: governed_binding_rules_instance_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX governed_binding_rules_instance_idx ON public.governed_binding_rules USING btree (binding_set_row_id, capability_instance_id);


--
-- Name: governed_binding_rules_source_endpoint_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX governed_binding_rules_source_endpoint_idx ON public.governed_binding_rules USING btree (binding_set_row_id, source_endpoint_ref);


--
-- Name: governed_binding_sets_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_binding_sets_scope_idx ON public.governed_binding_sets USING btree (mission_id, binding_set_id, version);


--
-- Name: governed_capability_instances_binding_set_instance_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_capability_instances_binding_set_instance_idx ON public.governed_capability_instances USING btree (binding_set_row_id, capability_instance_id);


--
-- Name: governed_capability_instances_binding_set_row_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX governed_capability_instances_binding_set_row_id_index ON public.governed_capability_instances USING btree (binding_set_row_id);


--
-- Name: governed_derived_telemetry_definitions_mission_id_point_id_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX governed_derived_telemetry_definitions_mission_id_point_id_inde ON public.governed_derived_telemetry_definitions USING btree (mission_id, point_id);


--
-- Name: governed_derived_telemetry_definitions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_derived_telemetry_definitions_scope_idx ON public.governed_derived_telemetry_definitions USING btree (mission_id, derived_definition_id, version);


--
-- Name: governed_limit_definitions_mission_id_point_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX governed_limit_definitions_mission_id_point_id_index ON public.governed_limit_definitions USING btree (mission_id, point_id);


--
-- Name: governed_limit_definitions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_limit_definitions_scope_idx ON public.governed_limit_definitions USING btree (mission_id, limit_definition_id, version);


--
-- Name: governed_packet_definition_fields_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_packet_definition_fields_scope_idx ON public.governed_packet_definition_fields USING btree (packet_definition_row_id, field_id);


--
-- Name: governed_packet_definitions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX governed_packet_definitions_scope_idx ON public.governed_packet_definitions USING btree (mission_id, packet_definition_id, version);


--
-- Name: ground_station_availability_provider_ref_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ground_station_availability_provider_ref_idx ON public.ground_station_availability_windows USING btree (mission_id, provider_ref) WHERE (provider_ref IS NOT NULL);


--
-- Name: ground_station_availability_windows_mission_id_ground_station_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ground_station_availability_windows_mission_id_ground_station_i ON public.ground_station_availability_windows USING btree (mission_id, ground_station_id, starts_at);


--
-- Name: ingress_archive_evidence_entries_mission_id_realized_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_mission_id_realized_contact_id ON public.ingress_archive_evidence_entries USING btree (mission_id, realized_contact_id, receipt_time);


--
-- Name: ingress_archive_evidence_entries_mission_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_mission_id_receipt_time_index ON public.ingress_archive_evidence_entries USING btree (mission_id, receipt_time);


--
-- Name: ingress_archive_evidence_entries_mission_id_source_ref_receipt_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_mission_id_source_ref_receipt_ ON public.ingress_archive_evidence_entries USING btree (mission_id, source_ref, receipt_time);


--
-- Name: ingress_archive_evidence_entries_mission_id_spacecraft_id_recei; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_mission_id_spacecraft_id_recei ON public.ingress_archive_evidence_entries USING btree (mission_id, spacecraft_id, receipt_time);


--
-- Name: ingress_archive_evidence_entries_object_key_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_object_key_index ON public.ingress_archive_evidence_entries USING btree (object_key);


--
-- Name: ingress_archive_evidence_entries_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_receipt_time_index ON public.ingress_archive_evidence_entries USING brin (receipt_time);


--
-- Name: ingress_archive_evidence_entries_segment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_archive_evidence_entries_segment_id_index ON public.ingress_archive_evidence_entries USING btree (segment_id);


--
-- Name: ingress_raw_evidence_mission_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_raw_evidence_mission_id_receipt_time_index ON public.ingress_raw_evidence USING btree (mission_id, receipt_time);


--
-- Name: ingress_raw_evidence_source_endpoint_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingress_raw_evidence_source_endpoint_idx ON public.ingress_raw_evidence USING btree (mission_id, source_endpoint_ref);


--
-- Name: job_outcome_resolutions_job_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX job_outcome_resolutions_job_id_index ON public.job_outcome_resolutions USING btree (job_id);


--
-- Name: job_outcome_resolutions_mission_id_resolved_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX job_outcome_resolutions_mission_id_resolved_at_index ON public.job_outcome_resolutions USING btree (mission_id, resolved_at);


--
-- Name: limit_definition_lifecycle_events_definition_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX limit_definition_lifecycle_events_definition_idx ON public.limit_definition_lifecycle_events USING btree (mission_id, limit_definition_id, limit_definition_version);


--
-- Name: limit_definition_lifecycle_events_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX limit_definition_lifecycle_events_scope_idx ON public.limit_definition_lifecycle_events USING btree (organization_id, mission_id, point_id, limit_set_name);


--
-- Name: managed_action_requests_evidence_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_action_requests_evidence_id_index ON public.managed_action_requests USING btree (evidence_id);


--
-- Name: managed_action_requests_mission_id_capability_instance_id_reque; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_action_requests_mission_id_capability_instance_id_reque ON public.managed_action_requests USING btree (mission_id, capability_instance_id, requested_at);


--
-- Name: managed_action_requests_packet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_action_requests_packet_id_index ON public.managed_action_requests USING btree (packet_id);


--
-- Name: managed_capability_records_evidence_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_capability_records_evidence_id_index ON public.managed_capability_records USING btree (evidence_id);


--
-- Name: managed_capability_records_mission_id_capability_instance_id_re; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_capability_records_mission_id_capability_instance_id_re ON public.managed_capability_records USING btree (mission_id, capability_instance_id, recorded_at);


--
-- Name: managed_capability_records_packet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_capability_records_packet_id_index ON public.managed_capability_records USING btree (packet_id);


--
-- Name: managed_timer_events_evidence_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_timer_events_evidence_id_index ON public.managed_timer_events USING btree (evidence_id);


--
-- Name: managed_timer_events_mission_id_capability_instance_id_occurred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_timer_events_mission_id_capability_instance_id_occurred ON public.managed_timer_events USING btree (mission_id, capability_instance_id, occurred_at);


--
-- Name: managed_timer_events_packet_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX managed_timer_events_packet_id_index ON public.managed_timer_events USING btree (packet_id);


--
-- Name: mission_binding_set_activations_generation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_binding_set_activations_generation_idx ON public.mission_binding_set_activations USING btree (mission_id, generation);


--
-- Name: mission_binding_set_activations_request_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_binding_set_activations_request_idx ON public.mission_binding_set_activations USING btree (activation_request_id) WHERE (activation_request_id IS NOT NULL);


--
-- Name: mission_binding_set_activations_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_binding_set_activations_scope_idx ON public.mission_binding_set_activations USING btree (mission_id, activated_at);


--
-- Name: mission_config_change_sets_mission_id_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_change_sets_mission_id_state_index ON public.mission_config_change_sets USING btree (mission_id, state);


--
-- Name: mission_config_change_sets_one_open_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_config_change_sets_one_open_idx ON public.mission_config_change_sets USING btree (mission_id) WHERE (state IN ('open', 'in_review'));


--
-- Name: mission_config_changes_change_set_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_changes_change_set_id_position_index ON public.mission_config_changes USING btree (change_set_id, "position");


--
-- Name: mission_config_ops_change_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_ops_change_id_position_index ON public.mission_config_ops USING btree (change_id, "position");


--
-- Name: mission_config_ops_change_set_id_kind_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_ops_change_set_id_kind_entity_id_index ON public.mission_config_ops USING btree (change_set_id, kind, entity_id);


--
-- Name: mission_config_reviews_change_set_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_reviews_change_set_id_index ON public.mission_config_reviews USING btree (change_set_id);


--
-- Name: mission_config_reviews_organization_id_decided_at_DESC_review_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "mission_config_reviews_organization_id_decided_at_DESC_review_i" ON public.mission_config_reviews USING btree (organization_id, decided_at DESC, review_id DESC);


--
-- Name: mission_config_revision_entries_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_revision_entries_entity_idx ON public.mission_config_revision_entries USING btree (mission_id, kind, entity_id, revision_number);


--
-- Name: mission_config_revision_entries_revision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_config_revision_entries_revision_id_index ON public.mission_config_revision_entries USING btree (revision_id);


--
-- Name: mission_config_revisions_number_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_config_revisions_number_idx ON public.mission_config_revisions USING btree (mission_id, revision_number);


--
-- Name: mission_event_rebuild_runs_mission_id_started_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_event_rebuild_runs_mission_id_started_at_index ON public.mission_event_rebuild_runs USING btree (mission_id, started_at);


--
-- Name: mission_events_mission_id_capability_instance_id_occurred_at_in; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_capability_instance_id_occurred_at_in ON public.mission_events USING btree (mission_id, capability_instance_id, occurred_at);


--
-- Name: mission_events_mission_id_category_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_category_occurred_at_index ON public.mission_events USING btree (mission_id, category, occurred_at);


--
-- Name: mission_events_mission_id_kind_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_kind_occurred_at_index ON public.mission_events USING btree (mission_id, kind, occurred_at);


--
-- Name: mission_events_mission_id_occurred_at_mission_event_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_occurred_at_mission_event_id_index ON public.mission_events USING btree (mission_id, occurred_at, mission_event_id);


--
-- Name: mission_events_mission_id_path_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_path_id_occurred_at_index ON public.mission_events USING btree (mission_id, path_id, occurred_at);


--
-- Name: mission_events_mission_id_realized_contact_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_realized_contact_id_occurred_at_index ON public.mission_events USING btree (mission_id, realized_contact_id, occurred_at);


--
-- Name: mission_events_mission_id_scheduled_contact_id_occurred_at_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_scheduled_contact_id_occurred_at_inde ON public.mission_events USING btree (mission_id, scheduled_contact_id, occurred_at);


--
-- Name: mission_events_mission_id_severity_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_severity_occurred_at_index ON public.mission_events USING btree (mission_id, severity, occurred_at);


--
-- Name: mission_events_mission_id_source_endpoint_ref_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_source_endpoint_ref_occurred_at_index ON public.mission_events USING btree (mission_id, source_endpoint_ref, occurred_at);


--
-- Name: mission_events_mission_id_source_record_kind_source_record_id_i; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_events_mission_id_source_record_kind_source_record_id_i ON public.mission_events USING btree (mission_id, source_record_kind, source_record_id);


--
-- Name: mission_events_mission_id_spacecraft_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_events_mission_id_spacecraft_id_occurred_at_index ON public.mission_events USING btree (mission_id, spacecraft_id, occurred_at);


--
-- Name: mission_model_comparison_reports_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_comparison_reports_identity_idx ON public.mission_model_comparison_reports USING btree (organization_id, mission_id, candidate_revision_id, binding_set_id, binding_set_version, report_sha256);


--
-- Name: mission_model_comparison_reports_no_binding_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_comparison_reports_no_binding_identity_idx ON public.mission_model_comparison_reports USING btree (organization_id, mission_id, candidate_revision_id, report_sha256) WHERE (binding_set_id IS NULL);


--
-- Name: mission_model_composition_numbers_number_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_composition_numbers_number_idx ON public.mission_model_composition_numbers USING btree (organization_id, mission_id, number);


--
-- Name: mission_model_diagnostics_organization_id_mission_id_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_model_diagnostics_organization_id_mission_id_code_index ON public.mission_model_diagnostics USING btree (organization_id, mission_id, code);


--
-- Name: mission_model_diagnostics_revision_id_severity_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_model_diagnostics_revision_id_severity_index ON public.mission_model_diagnostics USING btree (revision_id, severity);


--
-- Name: mission_model_effective_revisions_head_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_effective_revisions_head_idx ON public.mission_model_effective_revisions USING btree (organization_id, mission_id, composition_id, COALESCE(authored_head, ''::character varying), compiler_version);


--
-- Name: mission_model_effective_revisions_revision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_effective_revisions_revision_idx ON public.mission_model_effective_revisions USING btree (revision_id);


--
-- Name: mission_model_layers_mission_id_content_sha256_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_layers_mission_id_content_sha256_index ON public.mission_model_layers USING btree (mission_id, content_sha256);


--
-- Name: mission_model_layers_organization_id_mission_id_inserted_at_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_model_layers_organization_id_mission_id_inserted_at_ind ON public.mission_model_layers USING btree (organization_id, mission_id, inserted_at);


--
-- Name: mission_model_layers_tenant_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_layers_tenant_idx ON public.mission_model_layers USING btree (organization_id, mission_id, layer_id);


--
-- Name: mission_model_qualification_cases_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_model_qualification_cases_scope_idx ON public.mission_model_qualification_cases USING btree (organization_id, mission_id, status);


--
-- Name: mission_model_revision_layers_revision_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_revision_layers_revision_id_position_index ON public.mission_model_revision_layers USING btree (revision_id, "position");


--
-- Name: mission_model_revisions_mission_id_content_sha256_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_revisions_mission_id_content_sha256_index ON public.mission_model_revisions USING btree (mission_id, content_sha256);


--
-- Name: mission_model_revisions_organization_id_mission_id_inserted_at_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_model_revisions_organization_id_mission_id_inserted_at_ ON public.mission_model_revisions USING btree (organization_id, mission_id, inserted_at);


--
-- Name: mission_model_revisions_tenant_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_revisions_tenant_idx ON public.mission_model_revisions USING btree (organization_id, mission_id, revision_id, compiler_version);


--
-- Name: mission_model_runtime_plans_organization_id_mission_id_target_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_model_runtime_plans_organization_id_mission_id_target_i ON public.mission_model_runtime_plans USING btree (organization_id, mission_id, target);


--
-- Name: mission_model_runtime_plans_revision_id_target_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_model_runtime_plans_revision_id_target_index ON public.mission_model_runtime_plans USING btree (revision_id, target);


--
-- Name: mission_providers_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_providers_org_mission_idx ON public.mission_providers USING btree (organization_id, mission_id);


--
-- Name: mission_providers_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_providers_scope_idx ON public.mission_providers USING btree (mission_id, provider_id, version);


--
-- Name: mission_source_endpoints_reference_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_source_endpoints_reference_idx ON public.mission_source_endpoints USING btree (mission_id, COALESCE(spacecraft_id, ''::character varying), source_ref) WHERE (source_ref IS NOT NULL);


--
-- Name: mission_source_endpoints_source_ref_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_source_endpoints_source_ref_idx ON public.mission_source_endpoints USING btree (mission_id, source_ref);


--
-- Name: mission_source_endpoints_spacecraft_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_source_endpoints_spacecraft_idx ON public.mission_source_endpoints USING btree (mission_id, spacecraft_id);


--
-- Name: mission_spacecraft_active_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_spacecraft_active_mission_idx ON public.mission_spacecraft USING btree (mission_id) WHERE ((lifecycle_state)::text = 'active'::text);


--
-- Name: mission_spacecraft_org_mission_scid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_spacecraft_org_mission_scid_idx ON public.mission_spacecraft USING btree (organization_id, mission_id, scid) WHERE (scid IS NOT NULL);


--
-- Name: mission_spacecraft_org_mission_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_spacecraft_org_mission_type_idx ON public.mission_spacecraft USING btree (organization_id, mission_id, spacecraft_type_id) WHERE (spacecraft_type_id IS NOT NULL);


--
-- Name: mission_spacecraft_types_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mission_spacecraft_types_org_mission_idx ON public.mission_spacecraft_types USING btree (organization_id, mission_id);


--
-- Name: mission_spacecraft_types_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX mission_spacecraft_types_scope_idx ON public.mission_spacecraft_types USING btree (mission_id, spacecraft_type_id, version);


--
-- Name: missions_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX missions_org_mission_idx ON public.missions USING btree (organization_id, mission_id);


--
-- Name: missions_org_slug_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX missions_org_slug_idx ON public.missions USING btree (organization_id, slug);


--
-- Name: notifications_user_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_user_id_inserted_at_index ON public.notifications USING btree (user_id, inserted_at);


--
-- Name: notifications_user_id_read_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_user_id_read_at_index ON public.notifications USING btree (user_id, read_at);


--
-- Name: operational_events_category_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX operational_events_category_time_idx ON public.operational_events USING btree (organization_id, mission_id, category, occurred_at);


--
-- Name: operational_events_kind_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX operational_events_kind_time_idx ON public.operational_events USING btree (organization_id, mission_id, kind, occurred_at);


--
-- Name: operational_events_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX operational_events_replay_idx ON public.operational_events USING btree (organization_id, mission_id, replay_run_id);


--
-- Name: operational_events_scope_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX operational_events_scope_time_idx ON public.operational_events USING btree (organization_id, mission_id, occurred_at, event_id);


--
-- Name: operational_events_source_history_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX operational_events_source_history_idx ON public.operational_events USING btree (organization_id, mission_id, source_record_kind, occurred_at, event_id, replay_run_id);


--
-- Name: operational_events_source_record_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX operational_events_source_record_idx ON public.operational_events USING btree (mission_id, source_record_kind, source_record_id) WHERE ((source_record_kind IS NOT NULL) AND (source_record_id IS NOT NULL) AND (replay_run_id IS NULL));


--
-- Name: operational_events_source_record_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX operational_events_source_record_replay_idx ON public.operational_events USING btree (mission_id, source_record_kind, source_record_id, replay_run_id) WHERE ((source_record_kind IS NOT NULL) AND (source_record_id IS NOT NULL) AND (replay_run_id IS NOT NULL));


--
-- Name: operational_events_subject_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX operational_events_subject_idx ON public.operational_events USING btree (organization_id, mission_id, subject_kind, subject_id);


--
-- Name: ops_dashboards_org_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ops_dashboards_org_mission_idx ON public.ops_dashboards USING btree (organization_id, mission_id);


--
-- Name: ops_dashboards_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ops_dashboards_scope_idx ON public.ops_dashboards USING btree (mission_id, dashboard_id);


--
-- Name: organization_invitations_email_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_invitations_email_status_index ON public.organization_invitations USING btree (email, status);


--
-- Name: organization_invitations_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_invitations_expires_at_index ON public.organization_invitations USING btree (expires_at);


--
-- Name: organization_invitations_organization_id_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_invitations_organization_id_status_index ON public.organization_invitations USING btree (organization_id, status);


--
-- Name: organization_invitations_token_digest_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organization_invitations_token_digest_index ON public.organization_invitations USING btree (token_digest);


--
-- Name: organization_memberships_organization_id_lifecycle_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_memberships_organization_id_lifecycle_state_index ON public.organization_memberships USING btree (organization_id, lifecycle_state);


--
-- Name: organization_memberships_user_id_lifecycle_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_memberships_user_id_lifecycle_state_index ON public.organization_memberships USING btree (user_id, lifecycle_state);


--
-- Name: organization_memberships_user_id_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organization_memberships_user_id_organization_id_index ON public.organization_memberships USING btree (user_id, organization_id);


--
-- Name: organizations_slug_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organizations_slug_idx ON public.organizations USING btree (slug);


--
-- Name: partition_stream_keys_stream_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX partition_stream_keys_stream_idx ON public.partition_stream_keys USING btree (mission_id, partition_id, stream_key);


--
-- Name: platform_events_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_events_occurred_at_index ON public.platform_events USING btree (occurred_at);


--
-- Name: platform_events_organization_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_events_organization_id_occurred_at_index ON public.platform_events USING btree (organization_id, occurred_at);


--
-- Name: protocol_anomalies_anomaly_kind_protocol_family_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_anomalies_anomaly_kind_protocol_family_index ON public.protocol_anomalies USING btree (anomaly_kind, protocol_family);


--
-- Name: protocol_anomalies_mission_id_evidence_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_anomalies_mission_id_evidence_id_index ON public.protocol_anomalies USING btree (mission_id, evidence_id);


--
-- Name: protocol_anomalies_organization_id_mission_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_anomalies_organization_id_mission_id_index ON public.protocol_anomalies USING btree (organization_id, mission_id);


--
-- Name: protocol_anomalies_source_endpoint_ref_protocol_family_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_anomalies_source_endpoint_ref_protocol_family_index ON public.protocol_anomalies USING btree (source_endpoint_ref, protocol_family);


--
-- Name: protocol_archive_quarantine_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_quarantine_expiry_idx ON public.protocol_archive_quarantine USING btree (COALESCE(receipt_time, first_seen_at));


--
-- Name: protocol_archive_quarantine_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_quarantine_item_idx ON public.protocol_archive_quarantine USING btree (mission_id, realized_contact_id, error_code);


--
-- Name: protocol_archive_quarantine_record_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX protocol_archive_quarantine_record_idx ON public.protocol_archive_quarantine USING btree (mission_id, record_kind, record_id);


--
-- Name: protocol_archive_quarantine_resolved_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_quarantine_resolved_at_idx ON public.protocol_archive_quarantine_resolutions USING btree (resolved_at);


--
-- Name: protocol_archive_quarantine_resolved_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_quarantine_resolved_idx ON public.protocol_archive_quarantine_resolutions USING btree (mission_id, resolved_at);


--
-- Name: protocol_archive_record_identities_segment_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_record_identities_segment_id_index ON public.protocol_archive_record_identities USING btree (segment_id);


--
-- Name: protocol_archive_segments_archive_backend_mission_id_first_rece; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_segments_archive_backend_mission_id_first_rece ON public.protocol_archive_segments USING btree (archive_backend, mission_id, first_receipt_time, last_receipt_time);


--
-- Name: protocol_archive_segments_evidence_ids_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_segments_evidence_ids_index ON public.protocol_archive_segments USING gin (evidence_ids);


--
-- Name: protocol_archive_segments_last_receipt_brin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_archive_segments_last_receipt_brin ON public.protocol_archive_segments USING brin (last_receipt_time);


--
-- Name: protocol_archive_segments_object_key_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX protocol_archive_segments_object_key_index ON public.protocol_archive_segments USING btree (object_key);


--
-- Name: protocol_packet_records_mission_id_apid_sequence_count_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_packet_records_mission_id_apid_sequence_count_index ON public.protocol_packet_records USING btree (mission_id, apid, sequence_count);


--
-- Name: protocol_packet_records_mission_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_packet_records_mission_id_receipt_time_index ON public.protocol_packet_records USING btree (mission_id, receipt_time);


--
-- Name: protocol_packet_records_source_endpoint_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_packet_records_source_endpoint_idx ON public.protocol_packet_records USING btree (mission_id, source_endpoint_ref);


--
-- Name: protocol_transfer_frame_records_mission_id_evidence_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_transfer_frame_records_mission_id_evidence_id_index ON public.protocol_transfer_frame_records USING btree (mission_id, evidence_id);


--
-- Name: protocol_transfer_frame_records_organization_id_mission_id_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_transfer_frame_records_organization_id_mission_id_inde ON public.protocol_transfer_frame_records USING btree (organization_id, mission_id);


--
-- Name: protocol_transfer_frame_records_scid_vcid_frame_seq_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_transfer_frame_records_scid_vcid_frame_seq_index ON public.protocol_transfer_frame_records USING btree (scid, vcid, frame_seq);


--
-- Name: protocol_transfer_frame_records_source_endpoint_ref_protocol_fa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX protocol_transfer_frame_records_source_endpoint_ref_protocol_fa ON public.protocol_transfer_frame_records USING btree (source_endpoint_ref, protocol_family);


--
-- Name: provider_account_grants_mission_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_account_grants_mission_state_idx ON public.provider_account_grants USING btree (organization_id, mission_id, lifecycle_state);


--
-- Name: provider_account_grants_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_account_grants_org_scope_idx ON public.provider_account_grants USING btree (organization_id, mission_id, provider_account_grant_id, version);


--
-- Name: provider_account_grants_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_account_grants_scope_idx ON public.provider_account_grants USING btree (provider_account_grant_id, version);


--
-- Name: provider_account_versions_org_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_account_versions_org_scope_idx ON public.provider_account_versions USING btree (organization_id, provider_account_id, version);


--
-- Name: provider_account_versions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_account_versions_scope_idx ON public.provider_account_versions USING btree (provider_account_id, version);


--
-- Name: provider_accounts_org_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_accounts_org_id_idx ON public.provider_accounts USING btree (organization_id, provider_account_id);


--
-- Name: provider_accounts_org_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_accounts_org_state_idx ON public.provider_accounts USING btree (organization_id, lifecycle_state);


--
-- Name: provider_audit_entries_account_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_audit_entries_account_time_idx ON public.provider_audit_entries USING btree (organization_id, provider_account_id, recorded_at);


--
-- Name: provider_audit_entries_correlation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_audit_entries_correlation_idx ON public.provider_audit_entries USING btree (organization_id, correlation_id, recorded_at);


--
-- Name: provider_audit_entries_mission_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_audit_entries_mission_time_idx ON public.provider_audit_entries USING btree (organization_id, mission_id, recorded_at);


--
-- Name: provider_audit_entries_org_action_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_audit_entries_org_action_time_idx ON public.provider_audit_entries USING btree (organization_id, action, recorded_at);


--
-- Name: provider_audit_entries_org_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_audit_entries_org_time_idx ON public.provider_audit_entries USING btree (organization_id, recorded_at);


--
-- Name: provider_change_approvals_change_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_change_approvals_change_idx ON public.provider_change_approvals USING btree (provider_reservation_change_id);


--
-- Name: provider_credentials_account_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_credentials_account_status_idx ON public.provider_credentials USING btree (organization_id, provider_account_id, status);


--
-- Name: provider_event_cursors_claim_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_event_cursors_claim_idx ON public.provider_event_cursors USING btree (health, lease_expires_at);


--
-- Name: provider_event_cursors_stream_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_event_cursors_stream_idx ON public.provider_event_cursors USING btree (organization_id, provider_account_id, provider_account_version, environment_ref, channel_ref, stream_ref);


--
-- Name: provider_event_inbox_content_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_event_inbox_content_identity_idx ON public.provider_event_inbox USING btree (organization_id, provider_account_id, provider_account_version, environment_ref, channel_ref, provider_event_id, content_sha256);


--
-- Name: provider_event_inbox_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_event_inbox_identity_idx ON public.provider_event_inbox USING btree (organization_id, provider_account_id, provider_account_version, environment_ref, channel_ref, provider_event_id);


--
-- Name: provider_event_inbox_processing_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_event_inbox_processing_idx ON public.provider_event_inbox USING btree (processing_state, received_at);


--
-- Name: provider_evidence_account_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_evidence_account_time_idx ON public.provider_evidence USING btree (organization_id, provider_account_id, captured_at);


--
-- Name: provider_evidence_content_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_evidence_content_idx ON public.provider_evidence USING btree (organization_id, provider_account_id, schema_type, media_type, content_sha256);


--
-- Name: provider_reservation_changes_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_reservation_changes_identity_idx ON public.provider_reservation_changes USING btree (provider_reservation_id, change_identity);


--
-- Name: provider_reservation_changes_queue_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_reservation_changes_queue_idx ON public.provider_reservation_changes USING btree (organization_id, mission_id, lifecycle_state);


--
-- Name: provider_reservation_changes_revision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_reservation_changes_revision_idx ON public.provider_reservation_changes USING btree (provider_reservation_id, provider_revision);


--
-- Name: provider_reservations_contact_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_reservations_contact_idx ON public.provider_reservations USING btree (organization_id, mission_id, scheduled_contact_id);


--
-- Name: provider_reservations_contact_plan_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_reservations_contact_plan_idx ON public.provider_reservations USING btree (organization_id, mission_id, contact_plan_id, contact_plan_version) WHERE (contact_plan_id IS NOT NULL);


--
-- Name: provider_reservations_idempotency_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_reservations_idempotency_idx ON public.provider_reservations USING btree (mission_id, provider_profile_id, idempotency_key);


--
-- Name: provider_reservations_provider_idempotency_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_reservations_provider_idempotency_idx ON public.provider_reservations USING btree (mission_id, provider_id, idempotency_key) WHERE (provider_id IS NOT NULL);


--
-- Name: provider_reservations_provider_ref_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_reservations_provider_ref_idx ON public.provider_reservations USING btree (mission_id, provider_contact_ref) WHERE (provider_contact_ref IS NOT NULL);


--
-- Name: provider_reservations_reconciliation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_reservations_reconciliation_idx ON public.provider_reservations USING btree (organization_id, mission_id, lifecycle_state);


--
-- Name: provider_reservations_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX provider_reservations_scope_idx ON public.provider_reservations USING btree (mission_id, provider_reservation_id);


--
-- Name: provider_reservations_transport_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX provider_reservations_transport_idx ON public.provider_reservations USING btree (mission_id, transport_id, transport_version);


--
-- Name: realized_contacts_mission_id_lifecycle_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX realized_contacts_mission_id_lifecycle_state_index ON public.realized_contacts USING btree (mission_id, lifecycle_state);


--
-- Name: realized_contacts_mission_id_scheduled_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX realized_contacts_mission_id_scheduled_contact_id_index ON public.realized_contacts USING btree (mission_id, scheduled_contact_id);


--
-- Name: realized_contacts_scheduler_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX realized_contacts_scheduler_active_idx ON public.realized_contacts USING btree (realized_at, realized_contact_id) WHERE ((lifecycle_state)::text = 'active'::text);


--
-- Name: realized_contacts_scheduler_active_schedule_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX realized_contacts_scheduler_active_schedule_idx ON public.realized_contacts USING btree (mission_id, scheduled_contact_id, realized_contact_id) WHERE (((lifecycle_state)::text = 'active'::text) AND (scheduled_contact_id IS NOT NULL));


--
-- Name: realized_contacts_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX realized_contacts_scope_idx ON public.realized_contacts USING btree (mission_id, realized_contact_id);


--
-- Name: replay_dispatch_decisions_replay_run_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_dispatch_decisions_replay_run_id_index ON public.replay_dispatch_decisions USING btree (replay_run_id);


--
-- Name: replay_dispatch_work_items_dispatch_decision_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_dispatch_work_items_dispatch_decision_id_index ON public.replay_dispatch_work_items USING btree (dispatch_decision_id);


--
-- Name: replay_managed_action_requests_replay_run_id_capability_instanc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_managed_action_requests_replay_run_id_capability_instanc ON public.replay_managed_action_requests USING btree (replay_run_id, capability_instance_id);


--
-- Name: replay_managed_action_requests_replay_run_id_requested_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_managed_action_requests_replay_run_id_requested_at_index ON public.replay_managed_action_requests USING btree (replay_run_id, requested_at);


--
-- Name: replay_managed_capability_records_replay_run_id_capability_inst; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_managed_capability_records_replay_run_id_capability_inst ON public.replay_managed_capability_records USING btree (replay_run_id, capability_instance_id);


--
-- Name: replay_managed_capability_records_replay_run_id_recorded_at_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_managed_capability_records_replay_run_id_recorded_at_ind ON public.replay_managed_capability_records USING btree (replay_run_id, recorded_at);


--
-- Name: replay_managed_timer_events_replay_run_id_capability_instance_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_managed_timer_events_replay_run_id_capability_instance_i ON public.replay_managed_timer_events USING btree (replay_run_id, capability_instance_id);


--
-- Name: replay_managed_timer_events_replay_run_id_occurred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_managed_timer_events_replay_run_id_occurred_at_index ON public.replay_managed_timer_events USING btree (replay_run_id, occurred_at);


--
-- Name: replay_runs_mission_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_runs_mission_id_inserted_at_index ON public.replay_runs USING btree (mission_id, inserted_at);


--
-- Name: replay_telemetry_samples_replay_run_id_point_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX replay_telemetry_samples_replay_run_id_point_id_index ON public.replay_telemetry_samples USING btree (replay_run_id, point_id);


--
-- Name: scheduled_contact_revisions_change_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX scheduled_contact_revisions_change_idx ON public.scheduled_contact_revisions USING btree (provider_reservation_change_id) WHERE (provider_reservation_change_id IS NOT NULL);


--
-- Name: scheduled_contact_revisions_revision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX scheduled_contact_revisions_revision_idx ON public.scheduled_contact_revisions USING btree (scheduled_contact_id, revision);


--
-- Name: scheduled_contacts_mission_id_lifecycle_state_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_contacts_mission_id_lifecycle_state_index ON public.scheduled_contacts USING btree (mission_id, lifecycle_state);


--
-- Name: scheduled_contacts_mission_id_starts_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_contacts_mission_id_starts_at_index ON public.scheduled_contacts USING btree (mission_id, starts_at);


--
-- Name: scheduled_contacts_scheduler_completed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_contacts_scheduler_completed_idx ON public.scheduled_contacts USING btree (ends_at, scheduled_contact_id) WHERE (((lifecycle_state)::text = 'realized'::text) AND (ends_at IS NOT NULL));


--
-- Name: scheduled_contacts_scheduler_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_contacts_scheduler_due_idx ON public.scheduled_contacts USING btree (starts_at, scheduled_contact_id) WHERE ((lifecycle_state)::text = 'scheduled'::text);


--
-- Name: scheduled_contacts_scheduler_expired_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX scheduled_contacts_scheduler_expired_idx ON public.scheduled_contacts USING btree (ends_at, scheduled_contact_id) WHERE (((lifecycle_state)::text = 'scheduled'::text) AND (ends_at IS NOT NULL));


--
-- Name: scheduled_contacts_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX scheduled_contacts_scope_idx ON public.scheduled_contacts USING btree (mission_id, scheduled_contact_id);


--
-- Name: scoped_settings_revisions_version_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX scoped_settings_revisions_version_idx ON public.scoped_settings_revisions USING btree (organization_id, scope_key, section_id, version);


--
-- Name: semantic_alarm_acknowledgements_transition_id_acknowledged_at_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX semantic_alarm_acknowledgements_transition_id_acknowledged_at_i ON public.semantic_alarm_acknowledgements USING btree (transition_id, acknowledged_at);


--
-- Name: semantic_alarm_transitions_mission_id_parameter_id_receipt_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX semantic_alarm_transitions_mission_id_parameter_id_receipt_time ON public.semantic_alarm_transitions USING btree (mission_id, parameter_id, receipt_time);


--
-- Name: semantic_alarm_transitions_organization_id_mission_id_receipt_t; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX semantic_alarm_transitions_organization_id_mission_id_receipt_t ON public.semantic_alarm_transitions USING btree (organization_id, mission_id, receipt_time);


--
-- Name: semantic_alarm_transitions_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX semantic_alarm_transitions_scope_idx ON public.semantic_alarm_transitions USING btree (organization_id, mission_id, transition_id);


--
-- Name: semantic_latest_alarm_states_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX semantic_latest_alarm_states_scope_idx ON public.semantic_latest_alarm_states USING btree (mission_id, spacecraft_scope_id, parameter_id, policy_id);


--
-- Name: semantic_monitoring_evaluations_mission_id_parameter_id_receipt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX semantic_monitoring_evaluations_mission_id_parameter_id_receipt ON public.semantic_monitoring_evaluations USING btree (mission_id, parameter_id, receipt_time);


--
-- Name: semantic_monitoring_evaluations_organization_id_mission_id_rece; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX semantic_monitoring_evaluations_organization_id_mission_id_rece ON public.semantic_monitoring_evaluations USING btree (organization_id, mission_id, receipt_time);


--
-- Name: semantic_monitoring_evaluations_policy_id_update_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX semantic_monitoring_evaluations_policy_id_update_id_index ON public.semantic_monitoring_evaluations USING btree (policy_id, update_id);


--
-- Name: service_identities_token_digest_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX service_identities_token_digest_idx ON public.service_identities USING btree (token_digest);


--
-- Name: service_identity_accountables_organization_id_service_identity_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX service_identity_accountables_organization_id_service_identity_ ON public.service_identity_accountables USING btree (organization_id, service_identity_id);


--
-- Name: spacecraft_application_bindings_mission_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spacecraft_application_bindings_mission_idx ON public.spacecraft_application_bindings USING btree (organization_id, mission_id);


--
-- Name: spacecraft_application_bindings_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX spacecraft_application_bindings_scope_idx ON public.spacecraft_application_bindings USING btree (organization_id, mission_id, spacecraft_id, application_key);


--
-- Name: spacecraft_configuration_revisions_organization_id_mission_id_c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX spacecraft_configuration_revisions_organization_id_mission_id_c ON public.spacecraft_configuration_revisions USING btree (organization_id, mission_id, catalog_revision_id);


--
-- Name: spacecraft_configuration_revisions_version_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX spacecraft_configuration_revisions_version_idx ON public.spacecraft_configuration_revisions USING btree (organization_id, mission_id, spacecraft_id, version);


--
-- Name: staged_command_items_organization_id_mission_id_command_stage_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staged_command_items_organization_id_mission_id_command_stage_i ON public.staged_command_items USING btree (organization_id, mission_id, command_stage_id, item_order);


--
-- Name: staged_command_items_organization_id_mission_id_mission_model_r; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staged_command_items_organization_id_mission_id_mission_model_r ON public.staged_command_items USING btree (organization_id, mission_id, mission_model_revision_id);


--
-- Name: staged_command_items_organization_id_mission_id_source_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staged_command_items_organization_id_mission_id_source_endpoint ON public.staged_command_items USING btree (organization_id, mission_id, source_endpoint_ref);


--
-- Name: telemetry_backfill_lifecycle_events_observable_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_backfill_lifecycle_events_observable_idx ON public.telemetry_backfill_lifecycle_events USING btree (organization_id, mission_id, observable_id, source_from, source_to);


--
-- Name: telemetry_backfill_lifecycle_events_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_backfill_lifecycle_events_replay_idx ON public.telemetry_backfill_lifecycle_events USING btree (organization_id, mission_id, replay_run_id);


--
-- Name: telemetry_backfill_lifecycle_events_run_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_backfill_lifecycle_events_run_idx ON public.telemetry_backfill_lifecycle_events USING btree (backfill_run_id, occurred_at);


--
-- Name: telemetry_backfill_lifecycle_events_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_backfill_lifecycle_events_scope_idx ON public.telemetry_backfill_lifecycle_events USING btree (organization_id, mission_id, occurred_at);


--
-- Name: telemetry_backfill_lifecycle_events_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_backfill_lifecycle_events_source_idx ON public.telemetry_backfill_lifecycle_events USING btree (organization_id, mission_id, data_source_id, binding_id, occurred_at);


--
-- Name: telemetry_identity_decision_events_identity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_identity_decision_events_identity_idx ON public.telemetry_observation_identity_decision_events USING btree (organization_id, mission_id, observation_identity_id, occurred_at);


--
-- Name: telemetry_identity_decision_events_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_identity_decision_events_replay_idx ON public.telemetry_observation_identity_decision_events USING btree (organization_id, mission_id, replay_run_id);


--
-- Name: telemetry_identity_decision_events_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_identity_decision_events_scope_idx ON public.telemetry_observation_identity_decision_events USING btree (organization_id, mission_id, occurred_at);


--
-- Name: telemetry_latest_limit_state_rebuild_runs_mission_id_inserted_a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_latest_limit_state_rebuild_runs_mission_id_inserted_a ON public.telemetry_latest_limit_state_rebuild_runs USING btree (mission_id, inserted_at);


--
-- Name: telemetry_latest_limit_states_active_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_latest_limit_states_active_order_idx ON public.telemetry_latest_limit_states USING btree (mission_id, (
CASE normalized_state
    WHEN 'red'::text THEN 0
    WHEN 'yellow'::text THEN 1
    WHEN 'blue'::text THEN 2
    ELSE 3
END), receipt_time DESC, COALESCE(spacecraft_id, ''::character varying), point_id) WHERE violation;


--
-- Name: telemetry_latest_limit_states_mission_id_point_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_latest_limit_states_mission_id_point_name_index ON public.telemetry_latest_limit_states USING btree (mission_id, point_name);


--
-- Name: telemetry_latest_limit_states_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX telemetry_latest_limit_states_scope_idx ON public.telemetry_latest_limit_states USING btree (mission_id, spacecraft_scope_id, point_id);


--
-- Name: telemetry_latest_value_rebuild_runs_mission_id_inserted_at_inde; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_latest_value_rebuild_runs_mission_id_inserted_at_inde ON public.telemetry_latest_value_rebuild_runs USING btree (mission_id, inserted_at);


--
-- Name: telemetry_latest_values_mission_id_point_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_latest_values_mission_id_point_name_index ON public.telemetry_latest_values USING btree (mission_id, point_name);


--
-- Name: telemetry_latest_values_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX telemetry_latest_values_scope_idx ON public.telemetry_latest_values USING btree (mission_id, spacecraft_scope_id, point_id, realm, data_source_id, binding_id);


--
-- Name: telemetry_latest_values_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_latest_values_source_idx ON public.telemetry_latest_values USING btree (mission_id, realm, data_source_id, binding_id);


--
-- Name: telemetry_limit_evaluation_runs_mission_id_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_limit_evaluation_runs_mission_id_inserted_at_index ON public.telemetry_limit_evaluation_runs USING btree (mission_id, inserted_at);


--
-- Name: telemetry_limit_events_crossing_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_limit_events_crossing_idx ON public.telemetry_limit_events USING btree (mission_id, spacecraft_id, point_id, receipt_time DESC, limit_event_id DESC);


--
-- Name: telemetry_limit_events_mission_id_point_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_limit_events_mission_id_point_id_receipt_time_index ON public.telemetry_limit_events USING btree (mission_id, point_id, receipt_time);


--
-- Name: telemetry_limit_events_mission_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_limit_events_mission_id_receipt_time_index ON public.telemetry_limit_events USING btree (mission_id, receipt_time);


--
-- Name: telemetry_limit_events_mission_id_source_sample_type_sample_id_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_limit_events_mission_id_source_sample_type_sample_id_ ON public.telemetry_limit_events USING btree (mission_id, source_sample_type, sample_id);


--
-- Name: telemetry_observation_identity_states_replay_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_observation_identity_states_replay_idx ON public.telemetry_observation_identity_states USING btree (organization_id, mission_id, replay_run_id);


--
-- Name: telemetry_observation_identity_states_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_observation_identity_states_scope_idx ON public.telemetry_observation_identity_states USING btree (mission_id, realm, observable_id);


--
-- Name: telemetry_observation_identity_states_validity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_observation_identity_states_validity_idx ON public.telemetry_observation_identity_states USING btree (mission_id, validity_state);


--
-- Name: telemetry_samples_mission_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_samples_mission_id_receipt_time_index ON public.telemetry_samples USING btree (mission_id, receipt_time);


--
-- Name: telemetry_samples_point_id_receipt_time_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_samples_point_id_receipt_time_index ON public.telemetry_samples USING btree (point_id, receipt_time);


--
-- Name: transport_action_requests_mission_id_capability_instance_id_ind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_action_requests_mission_id_capability_instance_id_ind ON public.transport_action_requests USING btree (mission_id, capability_instance_id);


--
-- Name: transport_action_requests_mission_id_command_release_attempt_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_action_requests_mission_id_command_release_attempt_id ON public.transport_action_requests USING btree (mission_id, command_release_attempt_id);


--
-- Name: transport_action_requests_mission_id_command_request_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_action_requests_mission_id_command_request_id_index ON public.transport_action_requests USING btree (mission_id, command_request_id);


--
-- Name: transport_action_requests_mission_id_realized_contact_id_path_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_action_requests_mission_id_realized_contact_id_path_i ON public.transport_action_requests USING btree (mission_id, realized_contact_id, path_id);


--
-- Name: transport_capability_records_mission_id_capability_instance_id_; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_capability_records_mission_id_capability_instance_id_ ON public.transport_capability_records USING btree (mission_id, capability_instance_id);


--
-- Name: transport_capability_records_mission_id_realized_contact_id_pat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_capability_records_mission_id_realized_contact_id_pat ON public.transport_capability_records USING btree (mission_id, realized_contact_id, path_id);


--
-- Name: transport_protocol_checkpoint_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_protocol_checkpoint_order_idx ON public.transport_capability_records USING btree (((metadata ->> 'resource_id'::text)), (((metadata ->> 'checkpoint_revision'::text))::bigint)) WHERE ((event_kind)::text = 'protocol_checkpoint'::text);


--
-- Name: transport_protocol_checkpoint_revision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX transport_protocol_checkpoint_revision_idx ON public.transport_capability_records USING btree (((metadata ->> 'resource_id'::text)), ((metadata ->> 'checkpoint_revision'::text))) WHERE ((event_kind)::text = 'protocol_checkpoint'::text);


--
-- Name: transport_send_recovery_operation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX transport_send_recovery_operation_idx ON public.transport_action_requests USING btree (((metadata ->> 'resource_id'::text)), ((metadata ->> 'recovery_operation_id'::text))) WHERE (((action_kind)::text = 'provider_send_prepared'::text) AND ((metadata ->> 'recovery_operation_id'::text) IS NOT NULL));


--
-- Name: transport_send_resource_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_send_resource_status_idx ON public.transport_action_requests USING btree (((metadata ->> 'resource_id'::text)), ((metadata ->> 'send_status'::text))) WHERE ((action_kind)::text = 'provider_send_prepared'::text);


--
-- Name: transport_timer_events_mission_id_capability_instance_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_timer_events_mission_id_capability_instance_id_index ON public.transport_timer_events USING btree (mission_id, capability_instance_id);


--
-- Name: transport_timer_events_mission_id_realized_contact_id_path_id_i; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transport_timer_events_mission_id_realized_contact_id_path_id_i ON public.transport_timer_events USING btree (mission_id, realized_contact_id, path_id);


--
-- Name: user_local_credentials_user_id_provider_key_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_local_credentials_user_id_provider_key_index ON public.user_local_credentials USING btree (user_id, provider_key);


--
-- Name: user_session_tokens_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_session_tokens_expires_at_index ON public.user_session_tokens USING btree (expires_at);


--
-- Name: user_session_tokens_token_digest_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_session_tokens_token_digest_index ON public.user_session_tokens USING btree (token_digest);


--
-- Name: user_session_tokens_user_id_context_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_session_tokens_user_id_context_index ON public.user_session_tokens USING btree (user_id, context);


--
-- Name: users_confirmed_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_confirmed_at_index ON public.users USING btree (confirmed_at);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);


--
-- Name: activation_decisions activation_decisions_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activation_decisions_append_only_rows BEFORE DELETE OR UPDATE ON public.activation_decisions FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: activation_decisions activation_decisions_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activation_decisions_append_only_truncate BEFORE TRUNCATE ON public.activation_decisions FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: automation_grant_decisions automation_grant_decisions_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER automation_grant_decisions_append_only_rows BEFORE DELETE OR UPDATE ON public.automation_grant_decisions FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: automation_grant_decisions automation_grant_decisions_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER automation_grant_decisions_append_only_truncate BEFORE TRUNCATE ON public.automation_grant_decisions FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: command_approvals command_approvals_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER command_approvals_append_only_rows BEFORE DELETE OR UPDATE ON public.command_approvals FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: command_approvals command_approvals_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER command_approvals_append_only_truncate BEFORE TRUNCATE ON public.command_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: contact_plan_approvals contact_plan_approvals_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contact_plan_approvals_append_only_rows BEFORE DELETE OR UPDATE ON public.contact_plan_approvals FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: contact_plan_approvals contact_plan_approvals_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contact_plan_approvals_append_only_truncate BEFORE TRUNCATE ON public.contact_plan_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: contact_plan_submissions contact_plan_submissions_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contact_plan_submissions_append_only_rows BEFORE DELETE OR UPDATE ON public.contact_plan_submissions FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: contact_plan_submissions contact_plan_submissions_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contact_plan_submissions_append_only_truncate BEFORE TRUNCATE ON public.contact_plan_submissions FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: fleet_planning_policy_approvals fleet_planning_policy_approvals_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER fleet_planning_policy_approvals_append_only_rows BEFORE DELETE OR UPDATE ON public.fleet_planning_policy_approvals FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: fleet_planning_policy_approvals fleet_planning_policy_approvals_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER fleet_planning_policy_approvals_append_only_truncate BEFORE TRUNCATE ON public.fleet_planning_policy_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: frontend_release_activation_controls frontend_release_activation_controls_delete_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_activation_controls_delete_guard BEFORE DELETE ON public.frontend_release_activation_controls FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_activation_controls frontend_release_activation_controls_transition_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_activation_controls_transition_guard BEFORE UPDATE ON public.frontend_release_activation_controls FOR EACH ROW EXECUTE FUNCTION public.cadence_guard_frontend_release_activation_control();


--
-- Name: frontend_release_activation_controls frontend_release_activation_controls_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_activation_controls_truncate_protection BEFORE TRUNCATE ON public.frontend_release_activation_controls FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_activation_requests frontend_release_activation_requests_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_activation_requests_immutable BEFORE DELETE OR UPDATE ON public.frontend_release_activation_requests FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_activation_requests frontend_release_activation_requests_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_activation_requests_truncate_protection BEFORE TRUNCATE ON public.frontend_release_activation_requests FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_artifacts frontend_release_artifacts_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_artifacts_append_only BEFORE DELETE OR UPDATE ON public.frontend_release_artifacts FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_artifacts frontend_release_artifacts_size_cap; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_artifacts_size_cap BEFORE INSERT ON public.frontend_release_artifacts FOR EACH ROW EXECUTE FUNCTION public.cadence_enforce_frontend_release_artifact_size_cap();


--
-- Name: frontend_release_artifacts frontend_release_artifacts_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_artifacts_truncate_protection BEFORE TRUNCATE ON public.frontend_release_artifacts FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_catalog_bindings frontend_release_catalog_bindings_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_catalog_bindings_immutable BEFORE DELETE OR UPDATE ON public.frontend_release_catalog_bindings FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_catalog_bindings frontend_release_catalog_bindings_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_catalog_bindings_truncate_protection BEFORE TRUNCATE ON public.frontend_release_catalog_bindings FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_catalog_generations frontend_release_catalog_generations_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_catalog_generations_immutable BEFORE DELETE OR UPDATE ON public.frontend_release_catalog_generations FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_catalog_generations frontend_release_catalog_generations_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_catalog_generations_truncate_protection BEFORE TRUNCATE ON public.frontend_release_catalog_generations FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_catalog_publications frontend_release_catalog_publications_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_catalog_publications_append_only BEFORE DELETE OR UPDATE ON public.frontend_release_catalog_publications FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_catalog_publications frontend_release_catalog_publications_generation_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER frontend_release_catalog_publications_generation_guard AFTER INSERT ON public.frontend_release_catalog_publications DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.acceptance_state)::text = 'accepted'::text)) EXECUTE FUNCTION public.cadence_require_frontend_release_catalog_generation();


--
-- Name: frontend_release_catalog_publications frontend_release_catalog_publications_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_catalog_publications_truncate_protection BEFORE TRUNCATE ON public.frontend_release_catalog_publications FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_object_chunks frontend_release_object_chunks_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_object_chunks_append_only BEFORE DELETE OR UPDATE ON public.frontend_release_object_chunks FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_object_chunks frontend_release_object_chunks_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_object_chunks_truncate_protection BEFORE TRUNCATE ON public.frontend_release_object_chunks FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_objects frontend_release_objects_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_objects_append_only BEFORE DELETE OR UPDATE ON public.frontend_release_objects FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_objects frontend_release_objects_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_objects_truncate_protection BEFORE TRUNCATE ON public.frontend_release_objects FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_publications frontend_release_publications_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_publications_append_only BEFORE DELETE OR UPDATE ON public.frontend_release_publications FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_publications frontend_release_publications_truncate_protection; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_publications_truncate_protection BEFORE TRUNCATE ON public.frontend_release_publications FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_staged_object_chunks frontend_release_staged_object_chunks_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_staged_object_chunks_immutable BEFORE UPDATE ON public.frontend_release_staged_object_chunks FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: frontend_release_staged_objects frontend_release_staged_objects_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER frontend_release_staged_objects_immutable BEFORE UPDATE ON public.frontend_release_staged_objects FOR EACH ROW EXECUTE FUNCTION public.cadence_reject_frontend_release_publication_mutation();


--
-- Name: governed_packet_definition_fields governed_packet_definition_fields_fill_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER governed_packet_definition_fields_fill_only BEFORE UPDATE ON public.governed_packet_definition_fields FOR EACH ROW EXECUTE FUNCTION public.governed_packet_definition_field_fill_only();


--
-- Name: governed_packet_definition_fields governed_packet_definition_fields_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER governed_packet_definition_fields_no_delete BEFORE DELETE ON public.governed_packet_definition_fields FOR EACH ROW EXECUTE FUNCTION public.governed_packet_definition_immutable();


--
-- Name: governed_packet_definition_fields governed_packet_definition_fields_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER governed_packet_definition_fields_no_truncate BEFORE TRUNCATE ON public.governed_packet_definition_fields FOR EACH STATEMENT EXECUTE FUNCTION public.governed_packet_definition_no_truncate();


--
-- Name: governed_packet_definitions governed_packet_definitions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER governed_packet_definitions_immutable BEFORE DELETE OR UPDATE ON public.governed_packet_definitions FOR EACH ROW EXECUTE FUNCTION public.governed_packet_definition_immutable();


--
-- Name: governed_packet_definitions governed_packet_definitions_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER governed_packet_definitions_no_truncate BEFORE TRUNCATE ON public.governed_packet_definitions FOR EACH STATEMENT EXECUTE FUNCTION public.governed_packet_definition_no_truncate();


--
-- Name: mission_config_reviews mission_config_reviews_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_config_reviews_append_only_rows BEFORE DELETE OR UPDATE ON public.mission_config_reviews FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: mission_config_reviews mission_config_reviews_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_config_reviews_append_only_truncate BEFORE TRUNCATE ON public.mission_config_reviews FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: mission_config_revisions mission_config_revisions_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_config_revisions_append_only_rows BEFORE DELETE OR UPDATE ON public.mission_config_revisions FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: mission_config_revisions mission_config_revisions_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_config_revisions_append_only_truncate BEFORE TRUNCATE ON public.mission_config_revisions FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: mission_model_composition_layers mission_model_composition_layers_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_composition_layers_immutable BEFORE DELETE OR UPDATE ON public.mission_model_composition_layers FOR EACH ROW EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_composition_layers mission_model_composition_layers_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_composition_layers_no_truncate BEFORE TRUNCATE ON public.mission_model_composition_layers FOR EACH STATEMENT EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_composition_numbers mission_model_composition_numbers_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_composition_numbers_immutable BEFORE DELETE OR UPDATE ON public.mission_model_composition_numbers FOR EACH ROW EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_composition_numbers mission_model_composition_numbers_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_composition_numbers_no_truncate BEFORE TRUNCATE ON public.mission_model_composition_numbers FOR EACH STATEMENT EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_compositions mission_model_compositions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_compositions_immutable BEFORE DELETE OR UPDATE ON public.mission_model_compositions FOR EACH ROW EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_compositions mission_model_compositions_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_compositions_no_truncate BEFORE TRUNCATE ON public.mission_model_compositions FOR EACH STATEMENT EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_effective_revisions mission_model_effective_revisions_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_effective_revisions_immutable BEFORE DELETE OR UPDATE ON public.mission_model_effective_revisions FOR EACH ROW EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: mission_model_effective_revisions mission_model_effective_revisions_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mission_model_effective_revisions_no_truncate BEFORE TRUNCATE ON public.mission_model_effective_revisions FOR EACH STATEMENT EXECUTE FUNCTION public.mission_model_composition_immutable();


--
-- Name: missions missions_scope_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER missions_scope_immutable BEFORE UPDATE OF mission_id, organization_id ON public.missions FOR EACH ROW EXECUTE FUNCTION public.cadence_mission_scope_immutable();


--
-- Name: provider_change_approvals provider_change_approvals_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER provider_change_approvals_append_only_rows BEFORE DELETE OR UPDATE ON public.provider_change_approvals FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: provider_change_approvals provider_change_approvals_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER provider_change_approvals_append_only_truncate BEFORE TRUNCATE ON public.provider_change_approvals FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: service_identity_accountables service_identity_accountables_append_only_rows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER service_identity_accountables_append_only_rows BEFORE DELETE OR UPDATE ON public.service_identity_accountables FOR EACH ROW EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: service_identity_accountables service_identity_accountables_append_only_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER service_identity_accountables_append_only_truncate BEFORE TRUNCATE ON public.service_identity_accountables FOR EACH STATEMENT EXECUTE FUNCTION public.cadence_decision_record_append_only();


--
-- Name: activation_fleet_entries sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.activation_fleet_entries FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: activation_fleet_members sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.activation_fleet_members FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: activation_fleets sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.activation_fleets FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: alarm_episode_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.alarm_episode_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: alarm_episodes sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.alarm_episodes FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: background_jobs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.background_jobs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: combined_downlink_records sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.combined_downlink_records FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: command_approvals sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.command_approvals FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: command_group_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.command_group_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: command_groups sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.command_groups FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: command_queue_entries sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.command_queue_entries FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: command_requests sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.command_requests FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: command_stages sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.command_stages FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: comms_ground_stations sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.comms_ground_stations FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: comms_routing_rule_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.comms_routing_rule_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: comms_routing_rules sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.comms_routing_rules FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: comms_transports sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.comms_transports FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: contact_actions sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.contact_actions FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_deployments sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_deployments FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_investigation_presets sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_investigation_presets FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_library_items sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_library_items FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_lifecycle_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_lifecycle_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_playlists sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_playlists FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_shares sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_shares FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_snapshots sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_snapshots FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: dashboard_user_preferences sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.dashboard_user_preferences FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: derived_telemetry_evaluation_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.derived_telemetry_evaluation_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: derived_telemetry_latest_value_rebuild_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.derived_telemetry_latest_value_rebuild_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: derived_telemetry_latest_values sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.derived_telemetry_latest_values FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: derived_telemetry_samples sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.derived_telemetry_samples FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: downlink_diagnostics sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.downlink_diagnostics FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: downlink_observations sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.downlink_observations FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: governed_binding_sets sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.governed_binding_sets FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: governed_derived_telemetry_definitions sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.governed_derived_telemetry_definitions FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: governed_limit_definitions sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.governed_limit_definitions FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: governed_packet_definitions sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.governed_packet_definitions FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: ground_station_availability_windows sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.ground_station_availability_windows FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: ingress_raw_evidence sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.ingress_raw_evidence FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: managed_action_requests sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.managed_action_requests FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: managed_capability_records sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.managed_capability_records FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: managed_timer_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.managed_timer_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_active_binding_sets sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_active_binding_sets FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_binding_set_activations sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_binding_set_activations FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_event_rebuild_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_event_rebuild_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_providers sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_providers FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_source_endpoints sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_source_endpoints FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_spacecraft sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_spacecraft FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: mission_spacecraft_types sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.mission_spacecraft_types FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: ops_dashboards sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.ops_dashboards FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: protocol_anomalies sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.protocol_anomalies FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: protocol_packet_records sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.protocol_packet_records FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: protocol_transfer_frame_records sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.protocol_transfer_frame_records FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: provider_account_grants sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.provider_account_grants FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: provider_audit_entries sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.provider_audit_entries FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: realized_contacts sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.realized_contacts FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: replay_managed_action_requests sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.replay_managed_action_requests FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: replay_managed_capability_records sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.replay_managed_capability_records FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: replay_managed_timer_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.replay_managed_timer_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: replay_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.replay_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: replay_telemetry_samples sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.replay_telemetry_samples FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: scheduled_contacts sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.scheduled_contacts FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: spacecraft_config_overrides sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.spacecraft_config_overrides FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: staged_command_items sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.staged_command_items FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_latest_limit_state_rebuild_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_latest_limit_state_rebuild_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_latest_limit_states sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_latest_limit_states FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_latest_value_rebuild_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_latest_value_rebuild_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_latest_values sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_latest_values FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_limit_evaluation_runs sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_limit_evaluation_runs FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_limit_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_limit_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: telemetry_samples sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.telemetry_samples FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: transport_action_requests sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.transport_action_requests FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: transport_capability_records sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.transport_capability_records FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: transport_timer_events sync_organization_id_from_mission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_organization_id_from_mission BEFORE INSERT OR UPDATE OF mission_id, organization_id ON public.transport_timer_events FOR EACH ROW EXECUTE FUNCTION public.cadence_sync_organization_id_from_mission();


--
-- Name: activation_decisions activation_decisions_activation_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_decisions
    ADD CONSTRAINT activation_decisions_activation_request_id_fkey FOREIGN KEY (activation_request_id) REFERENCES public.activation_requests(activation_request_id) ON DELETE RESTRICT;


--
-- Name: activation_executions activation_executions_activation_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_executions
    ADD CONSTRAINT activation_executions_activation_request_id_fkey FOREIGN KEY (activation_request_id) REFERENCES public.activation_requests(activation_request_id) ON DELETE RESTRICT;


--
-- Name: activation_fleet_entries activation_fleet_entries_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_fleet_entries
    ADD CONSTRAINT activation_fleet_entries_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: activation_fleet_members activation_fleet_members_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_fleet_members
    ADD CONSTRAINT activation_fleet_members_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: activation_fleets activation_fleets_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_fleets
    ADD CONSTRAINT activation_fleets_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: activation_requests activation_requests_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_requests
    ADD CONSTRAINT activation_requests_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: alarm_episode_events alarm_episode_events_episode_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alarm_episode_events
    ADD CONSTRAINT alarm_episode_events_episode_id_fkey FOREIGN KEY (episode_id) REFERENCES public.alarm_episodes(episode_id) ON DELETE CASCADE;


--
-- Name: alarm_episode_events alarm_episode_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alarm_episode_events
    ADD CONSTRAINT alarm_episode_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: alarm_episodes alarm_episodes_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alarm_episodes
    ADD CONSTRAINT alarm_episodes_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: application_dispatch_work_items application_dispatch_work_items_dispatch_decision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_dispatch_work_items
    ADD CONSTRAINT application_dispatch_work_items_dispatch_decision_id_fkey FOREIGN KEY (dispatch_decision_id) REFERENCES public.application_dispatch_decisions(dispatch_decision_id) ON DELETE CASCADE;


--
-- Name: application_installation_events application_installation_events_installation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_installation_events
    ADD CONSTRAINT application_installation_events_installation_fk FOREIGN KEY (application_installation_id) REFERENCES public.application_installations(application_installation_id) ON DELETE CASCADE;


--
-- Name: application_installations application_installations_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_installations
    ADD CONSTRAINT application_installations_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id) ON DELETE CASCADE;


--
-- Name: application_installations application_installations_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_installations
    ADD CONSTRAINT application_installations_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id) ON DELETE CASCADE;


--
-- Name: application_packet_binding_configurations application_packet_binding_configurations_installation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_binding_configurations
    ADD CONSTRAINT application_packet_binding_configurations_installation_fk FOREIGN KEY (application_installation_id) REFERENCES public.application_installations(application_installation_id) ON DELETE CASCADE;


--
-- Name: application_packet_binding_configurations application_packet_binding_configurations_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_binding_configurations
    ADD CONSTRAINT application_packet_binding_configurations_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id) ON DELETE CASCADE;


--
-- Name: application_packet_binding_configurations application_packet_binding_configurations_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_binding_configurations
    ADD CONSTRAINT application_packet_binding_configurations_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id) ON DELETE CASCADE;


--
-- Name: application_packet_binding_resources application_packet_binding_resources_binding_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_binding_resources
    ADD CONSTRAINT application_packet_binding_resources_binding_fk FOREIGN KEY (packet_binding_id) REFERENCES public.application_packet_bindings(packet_binding_id) ON DELETE CASCADE;


--
-- Name: application_packet_bindings application_packet_bindings_configuration_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_packet_bindings
    ADD CONSTRAINT application_packet_bindings_configuration_fk FOREIGN KEY (packet_binding_configuration_id) REFERENCES public.application_packet_binding_configurations(packet_binding_configuration_id) ON DELETE CASCADE;


--
-- Name: automation_grants automation_grants_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_grants
    ADD CONSTRAINT automation_grants_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: automation_grants automation_grants_policy_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_grants
    ADD CONSTRAINT automation_grants_policy_version_fk FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version) REFERENCES public.fleet_planning_policy_versions(organization_id, mission_id, fleet_planning_policy_id, version);


--
-- Name: automation_grants automation_grants_service_identity_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_grants
    ADD CONSTRAINT automation_grants_service_identity_fk FOREIGN KEY (service_identity_id) REFERENCES public.service_identities(service_identity_id);


--
-- Name: background_jobs background_jobs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.background_jobs
    ADD CONSTRAINT background_jobs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: catalog_artifacts catalog_artifacts_catalog_database_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_artifacts
    ADD CONSTRAINT catalog_artifacts_catalog_database_id_fkey FOREIGN KEY (catalog_database_id) REFERENCES public.catalog_databases(catalog_database_id);


--
-- Name: catalog_artifacts catalog_artifacts_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_artifacts
    ADD CONSTRAINT catalog_artifacts_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: catalog_databases catalog_databases_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_databases
    ADD CONSTRAINT catalog_databases_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: catalog_import_runs catalog_import_runs_artifact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_import_runs
    ADD CONSTRAINT catalog_import_runs_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES public.catalog_artifacts(artifact_id);


--
-- Name: catalog_import_runs catalog_import_runs_catalog_database_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_import_runs
    ADD CONSTRAINT catalog_import_runs_catalog_database_id_fkey FOREIGN KEY (catalog_database_id) REFERENCES public.catalog_databases(catalog_database_id);


--
-- Name: catalog_import_runs catalog_import_runs_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_import_runs
    ADD CONSTRAINT catalog_import_runs_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: catalog_revisions catalog_revisions_artifact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES public.catalog_artifacts(artifact_id);


--
-- Name: catalog_revisions catalog_revisions_catalog_database_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_catalog_database_id_fkey FOREIGN KEY (catalog_database_id) REFERENCES public.catalog_databases(catalog_database_id);


--
-- Name: catalog_revisions catalog_revisions_import_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_import_run_id_fkey FOREIGN KEY (import_run_id) REFERENCES public.catalog_import_runs(import_run_id);


--
-- Name: catalog_revisions catalog_revisions_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: catalog_revisions catalog_revisions_mission_model_layer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_mission_model_layer_id_fkey FOREIGN KEY (mission_model_layer_id) REFERENCES public.mission_model_layers(layer_id);


--
-- Name: catalog_revisions catalog_revisions_mission_model_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_revisions
    ADD CONSTRAINT catalog_revisions_mission_model_revision_id_fkey FOREIGN KEY (mission_model_revision_id) REFERENCES public.mission_model_revisions(revision_id);


--
-- Name: combined_downlink_records combined_downlink_records_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.combined_downlink_records
    ADD CONSTRAINT combined_downlink_records_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: command_approvals command_approvals_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_approvals
    ADD CONSTRAINT command_approvals_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: command_approvals command_approvals_request_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_approvals
    ADD CONSTRAINT command_approvals_request_fk FOREIGN KEY (organization_id, mission_id, command_request_id) REFERENCES public.command_requests(organization_id, mission_id, command_request_id);


--
-- Name: command_group_events command_group_events_command_group_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_group_events
    ADD CONSTRAINT command_group_events_command_group_id_fkey FOREIGN KEY (command_group_id) REFERENCES public.command_groups(command_group_id) ON DELETE CASCADE;


--
-- Name: command_queue_entries command_queue_entries_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_queue_entries
    ADD CONSTRAINT command_queue_entries_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: command_queue_entries command_queue_entries_request_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_queue_entries
    ADD CONSTRAINT command_queue_entries_request_fk FOREIGN KEY (organization_id, mission_id, command_request_id) REFERENCES public.command_requests(organization_id, mission_id, command_request_id);


--
-- Name: command_requests command_requests_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_requests
    ADD CONSTRAINT command_requests_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: command_stages command_stages_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.command_stages
    ADD CONSTRAINT command_stages_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: comms_ground_stations comms_ground_stations_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_ground_stations
    ADD CONSTRAINT comms_ground_stations_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: comms_routing_rule_events comms_routing_rule_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_routing_rule_events
    ADD CONSTRAINT comms_routing_rule_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: comms_routing_rules comms_routing_rules_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_routing_rules
    ADD CONSTRAINT comms_routing_rules_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: comms_transports comms_transports_mission_provider_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_transports
    ADD CONSTRAINT comms_transports_mission_provider_fk FOREIGN KEY (mission_id, mission_provider_id, mission_provider_version) REFERENCES public.mission_providers(mission_id, provider_id, version);


--
-- Name: comms_transports comms_transports_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comms_transports
    ADD CONSTRAINT comms_transports_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: contact_actions contact_actions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_actions
    ADD CONSTRAINT contact_actions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: contact_opportunity_snapshots contact_opportunity_snapshots_requirement_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_requirement_version_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id, contact_requirement_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version);


--
-- Name: contact_opportunity_snapshots contact_opportunity_snapshots_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_run_fk FOREIGN KEY (contact_planning_run_id) REFERENCES public.contact_planning_runs(contact_planning_run_id);


--
-- Name: contact_opportunity_snapshots contact_opportunity_snapshots_search_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_opportunity_snapshots
    ADD CONSTRAINT contact_opportunity_snapshots_search_fk FOREIGN KEY (contact_planning_search_id) REFERENCES public.contact_planning_searches(contact_planning_search_id);


--
-- Name: contact_plan_approvals contact_plan_approvals_automation_grant_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_approvals
    ADD CONSTRAINT contact_plan_approvals_automation_grant_fk FOREIGN KEY (automation_grant_id) REFERENCES public.automation_grants(automation_grant_id);


--
-- Name: contact_plan_approvals contact_plan_approvals_plan_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_approvals
    ADD CONSTRAINT contact_plan_approvals_plan_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: contact_plan_execution_items contact_plan_execution_items_plan_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_plan_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: contact_plan_execution_items contact_plan_execution_items_reservation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_reservation_fk FOREIGN KEY (provider_reservation_id) REFERENCES public.provider_reservations(provider_reservation_id);


--
-- Name: contact_plan_execution_items contact_plan_execution_items_snapshot_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_snapshot_fk FOREIGN KEY (contact_opportunity_snapshot_id) REFERENCES public.contact_opportunity_snapshots(contact_opportunity_snapshot_id);


--
-- Name: contact_plan_opportunity_refs contact_plan_opportunity_refs_plan_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_opportunity_refs
    ADD CONSTRAINT contact_plan_opportunity_refs_plan_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: contact_plan_opportunity_refs contact_plan_opportunity_refs_snapshot_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_opportunity_refs
    ADD CONSTRAINT contact_plan_opportunity_refs_snapshot_fk FOREIGN KEY (contact_opportunity_snapshot_id) REFERENCES public.contact_opportunity_snapshots(contact_opportunity_snapshot_id);


--
-- Name: contact_plan_requirement_refs contact_plan_requirement_refs_plan_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_requirement_refs
    ADD CONSTRAINT contact_plan_requirement_refs_plan_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: contact_plan_requirement_refs contact_plan_requirement_refs_requirement_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_requirement_refs
    ADD CONSTRAINT contact_plan_requirement_refs_requirement_version_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id, contact_requirement_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version);


--
-- Name: contact_plan_run_refs contact_plan_run_refs_plan_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_run_refs
    ADD CONSTRAINT contact_plan_run_refs_plan_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: contact_plan_run_refs contact_plan_run_refs_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_run_refs
    ADD CONSTRAINT contact_plan_run_refs_run_fk FOREIGN KEY (contact_planning_run_id) REFERENCES public.contact_planning_runs(contact_planning_run_id);


--
-- Name: contact_plan_versions contact_plan_versions_plan_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plan_versions
    ADD CONSTRAINT contact_plan_versions_plan_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id) REFERENCES public.contact_plans(organization_id, mission_id, contact_plan_id);


--
-- Name: contact_planning_runs contact_planning_runs_requirement_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_planning_runs
    ADD CONSTRAINT contact_planning_runs_requirement_version_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id, contact_requirement_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version);


--
-- Name: contact_planning_searches contact_planning_searches_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_planning_searches
    ADD CONSTRAINT contact_planning_searches_run_fk FOREIGN KEY (contact_planning_run_id) REFERENCES public.contact_planning_runs(contact_planning_run_id);


--
-- Name: contact_plans contact_plans_approved_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plans
    ADD CONSTRAINT contact_plans_approved_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, approved_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_plans contact_plans_current_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plans
    ADD CONSTRAINT contact_plans_current_version_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, current_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_plans contact_plans_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_plans
    ADD CONSTRAINT contact_plans_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: contact_requirement_occurrences contact_requirement_occurrences_requirement_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_requirement_version_fk FOREIGN KEY (organization_id, mission_id, generated_contact_requirement_id, generated_contact_requirement_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version);


--
-- Name: contact_requirement_occurrences contact_requirement_occurrences_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id);


--
-- Name: contact_requirement_occurrences contact_requirement_occurrences_template_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_template_version_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_template_id, contact_requirement_template_version) REFERENCES public.contact_requirement_template_versions(organization_id, mission_id, contact_requirement_template_id, version);


--
-- Name: contact_requirement_template_versions contact_requirement_template_versions_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id);


--
-- Name: contact_requirement_template_versions contact_requirement_template_versions_template_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_template_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_template_id) REFERENCES public.contact_requirement_templates(organization_id, mission_id, contact_requirement_template_id);


--
-- Name: contact_requirement_templates contact_requirement_templates_current_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_current_version_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_template_id, current_version) REFERENCES public.contact_requirement_template_versions(organization_id, mission_id, contact_requirement_template_id, version) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_requirement_templates contact_requirement_templates_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: contact_requirement_versions contact_requirement_versions_requirement_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_requirement_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id) REFERENCES public.contact_requirements(organization_id, mission_id, contact_requirement_id);


--
-- Name: contact_requirement_versions contact_requirement_versions_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirement_versions
    ADD CONSTRAINT contact_requirement_versions_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id);


--
-- Name: contact_requirements contact_requirements_current_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirements
    ADD CONSTRAINT contact_requirements_current_version_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id, current_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: contact_requirements contact_requirements_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_requirements
    ADD CONSTRAINT contact_requirements_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_deployments dashboard_deployments_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_deployments
    ADD CONSTRAINT dashboard_deployments_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_deployments dashboard_deployments_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_deployments
    ADD CONSTRAINT dashboard_deployments_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_investigation_presets dashboard_investigation_presets_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_investigation_presets
    ADD CONSTRAINT dashboard_investigation_presets_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_investigation_presets dashboard_investigation_presets_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_investigation_presets
    ADD CONSTRAINT dashboard_investigation_presets_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_library_items dashboard_library_items_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_library_items
    ADD CONSTRAINT dashboard_library_items_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_library_versions dashboard_library_versions_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_library_versions
    ADD CONSTRAINT dashboard_library_versions_item_fk FOREIGN KEY (dashboard_library_item_id) REFERENCES public.dashboard_library_items(dashboard_library_item_id) ON DELETE CASCADE;


--
-- Name: dashboard_lifecycle_events dashboard_lifecycle_events_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_lifecycle_events
    ADD CONSTRAINT dashboard_lifecycle_events_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_lifecycle_events dashboard_lifecycle_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_lifecycle_events
    ADD CONSTRAINT dashboard_lifecycle_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_playlists dashboard_playlists_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_playlists
    ADD CONSTRAINT dashboard_playlists_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_runtime_invalidation_decision_events dashboard_runtime_invalidation_decisions_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_runtime_invalidation_decision_events
    ADD CONSTRAINT dashboard_runtime_invalidation_decisions_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_runtime_invalidation_decision_events dashboard_runtime_invalidation_decisions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_runtime_invalidation_decision_events
    ADD CONSTRAINT dashboard_runtime_invalidation_decisions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_shares dashboard_shares_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_shares
    ADD CONSTRAINT dashboard_shares_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_shares dashboard_shares_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_shares
    ADD CONSTRAINT dashboard_shares_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_snapshots dashboard_snapshots_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT dashboard_snapshots_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_snapshots dashboard_snapshots_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_snapshots
    ADD CONSTRAINT dashboard_snapshots_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_user_preferences dashboard_user_preferences_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: dashboard_user_preferences dashboard_user_preferences_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: dashboard_user_preferences dashboard_user_preferences_user_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_user_preferences
    ADD CONSTRAINT dashboard_user_preferences_user_fk FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: dashboard_versions dashboard_versions_dashboard_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dashboard_versions
    ADD CONSTRAINT dashboard_versions_dashboard_fk FOREIGN KEY (dashboard_id) REFERENCES public.ops_dashboards(dashboard_id) ON DELETE CASCADE;


--
-- Name: data_source_binding_events data_source_binding_events_binding_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_binding_events
    ADD CONSTRAINT data_source_binding_events_binding_fk FOREIGN KEY (binding_id) REFERENCES public.data_source_bindings(binding_id);


--
-- Name: data_source_binding_events data_source_binding_events_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_binding_events
    ADD CONSTRAINT data_source_binding_events_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: data_source_binding_events data_source_binding_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_binding_events
    ADD CONSTRAINT data_source_binding_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: data_source_bindings data_source_bindings_data_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_bindings
    ADD CONSTRAINT data_source_bindings_data_source_fk FOREIGN KEY (data_source_id) REFERENCES public.data_source_definitions(data_source_id);


--
-- Name: data_source_bindings data_source_bindings_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_bindings
    ADD CONSTRAINT data_source_bindings_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: data_source_bindings data_source_bindings_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_bindings
    ADD CONSTRAINT data_source_bindings_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: data_source_credential_events data_source_credential_events_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: data_source_credential_events data_source_credential_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: data_source_credential_events data_source_credential_events_ref_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_ref_fk FOREIGN KEY (credentials_ref) REFERENCES public.data_source_credential_references(credentials_ref);


--
-- Name: data_source_credential_references data_source_credentials_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_references
    ADD CONSTRAINT data_source_credentials_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: data_source_credential_references data_source_credentials_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_credential_references
    ADD CONSTRAINT data_source_credentials_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: data_source_definition_events data_source_definition_events_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: data_source_definition_events data_source_definition_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: data_source_definition_events data_source_definition_events_source_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definition_events
    ADD CONSTRAINT data_source_definition_events_source_fk FOREIGN KEY (data_source_id) REFERENCES public.data_source_definitions(data_source_id);


--
-- Name: data_source_definitions data_source_definitions_credentials_ref_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definitions
    ADD CONSTRAINT data_source_definitions_credentials_ref_fk FOREIGN KEY (credentials_ref) REFERENCES public.data_source_credential_references(credentials_ref);


--
-- Name: data_source_definitions data_source_definitions_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definitions
    ADD CONSTRAINT data_source_definitions_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: data_source_definitions data_source_definitions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_source_definitions
    ADD CONSTRAINT data_source_definitions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: derived_telemetry_evaluation_runs derived_telemetry_evaluation_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_evaluation_runs
    ADD CONSTRAINT derived_telemetry_evaluation_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: derived_telemetry_latest_value_rebuild_runs derived_telemetry_latest_value_rebuild_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_latest_value_rebuild_runs
    ADD CONSTRAINT derived_telemetry_latest_value_rebuild_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: derived_telemetry_latest_values derived_telemetry_latest_values_derived_sample_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_latest_values
    ADD CONSTRAINT derived_telemetry_latest_values_derived_sample_id_fkey FOREIGN KEY (derived_sample_id) REFERENCES public.derived_telemetry_samples(derived_sample_id) ON DELETE CASCADE;


--
-- Name: derived_telemetry_latest_values derived_telemetry_latest_values_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_latest_values
    ADD CONSTRAINT derived_telemetry_latest_values_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: derived_telemetry_samples derived_telemetry_samples_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_samples
    ADD CONSTRAINT derived_telemetry_samples_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: derived_telemetry_samples derived_telemetry_samples_trigger_sample_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_telemetry_samples
    ADD CONSTRAINT derived_telemetry_samples_trigger_sample_id_fkey FOREIGN KEY (trigger_sample_id) REFERENCES public.telemetry_samples(sample_id) ON DELETE CASCADE;


--
-- Name: downlink_diagnostics downlink_diagnostics_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downlink_diagnostics
    ADD CONSTRAINT downlink_diagnostics_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: downlink_observations downlink_observations_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.downlink_observations
    ADD CONSTRAINT downlink_observations_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: fleet_automation_actions fleet_automation_actions_grant_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_grant_fk FOREIGN KEY (automation_grant_id) REFERENCES public.automation_grants(automation_grant_id);


--
-- Name: fleet_automation_actions fleet_automation_actions_plan_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_plan_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: fleet_automation_actions fleet_automation_actions_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_run_fk FOREIGN KEY (fleet_planning_run_id) REFERENCES public.fleet_planning_runs(fleet_planning_run_id);


--
-- Name: fleet_planning_decisions fleet_planning_decisions_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_decisions
    ADD CONSTRAINT fleet_planning_decisions_run_fk FOREIGN KEY (fleet_planning_run_id) REFERENCES public.fleet_planning_runs(fleet_planning_run_id);


--
-- Name: fleet_planning_decisions fleet_planning_decisions_snapshot_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_decisions
    ADD CONSTRAINT fleet_planning_decisions_snapshot_fk FOREIGN KEY (contact_opportunity_snapshot_id) REFERENCES public.contact_opportunity_snapshots(contact_opportunity_snapshot_id);


--
-- Name: fleet_planning_policies fleet_planning_policies_active_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_active_version_fk FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, active_version) REFERENCES public.fleet_planning_policy_versions(organization_id, mission_id, fleet_planning_policy_id, version) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: fleet_planning_policies fleet_planning_policies_current_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_current_version_fk FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, current_version) REFERENCES public.fleet_planning_policy_versions(organization_id, mission_id, fleet_planning_policy_id, version) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: fleet_planning_policies fleet_planning_policies_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: fleet_planning_policy_approvals fleet_planning_policy_approvals_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policy_approvals
    ADD CONSTRAINT fleet_planning_policy_approvals_version_fk FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version) REFERENCES public.fleet_planning_policy_versions(organization_id, mission_id, fleet_planning_policy_id, version);


--
-- Name: fleet_planning_policy_versions fleet_planning_policy_versions_policy_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_policy_versions
    ADD CONSTRAINT fleet_planning_policy_versions_policy_fk FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id) REFERENCES public.fleet_planning_policies(organization_id, mission_id, fleet_planning_policy_id);


--
-- Name: fleet_planning_run_requirement_refs fleet_planning_run_requirement_refs_planning_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_planning_run_fk FOREIGN KEY (contact_planning_run_id) REFERENCES public.contact_planning_runs(contact_planning_run_id);


--
-- Name: fleet_planning_run_requirement_refs fleet_planning_run_requirement_refs_requirement_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_requirement_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id, contact_requirement_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version);


--
-- Name: fleet_planning_run_requirement_refs fleet_planning_run_requirement_refs_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_run_fk FOREIGN KEY (fleet_planning_run_id) REFERENCES public.fleet_planning_runs(fleet_planning_run_id);


--
-- Name: fleet_planning_runs fleet_planning_runs_candidate_plan_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_candidate_plan_fk FOREIGN KEY (organization_id, mission_id, candidate_contact_plan_id, candidate_contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: fleet_planning_runs fleet_planning_runs_policy_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_policy_version_fk FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version) REFERENCES public.fleet_planning_policy_versions(organization_id, mission_id, fleet_planning_policy_id, version);


--
-- Name: fleet_planning_runs fleet_planning_runs_source_plan_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_source_plan_fk FOREIGN KEY (organization_id, mission_id, source_contact_plan_id, source_contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: fleet_planning_runs fleet_planning_runs_source_run_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_source_run_fk FOREIGN KEY (source_fleet_planning_run_id) REFERENCES public.fleet_planning_runs(fleet_planning_run_id);


--
-- Name: frontend_release_catalog_bindings frcb_current_release_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_bindings
    ADD CONSTRAINT frcb_current_release_fk FOREIGN KEY (current_publication_id, current_release_id) REFERENCES public.frontend_release_publications(publication_id, release_id) MATCH FULL ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: frontend_release_catalog_bindings frcb_previous_release_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_bindings
    ADD CONSTRAINT frcb_previous_release_fk FOREIGN KEY (previous_publication_id, previous_release_id) REFERENCES public.frontend_release_publications(publication_id, release_id) MATCH FULL ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: frontend_release_activation_controls frontend_release_activation_controls_legacy_catalog_publication; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_activation_controls
    ADD CONSTRAINT frontend_release_activation_controls_legacy_catalog_publication FOREIGN KEY (legacy_catalog_publication_id) REFERENCES public.frontend_release_catalog_publications(publication_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_activation_requests frontend_release_activation_requests_catalog_publication_id_fke; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_activation_requests
    ADD CONSTRAINT frontend_release_activation_requests_catalog_publication_id_fke FOREIGN KEY (catalog_publication_id) REFERENCES public.frontend_release_catalog_publications(publication_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_activation_requests frontend_release_activation_requests_generation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_activation_requests
    ADD CONSTRAINT frontend_release_activation_requests_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.frontend_release_catalog_generations(generation_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_artifacts frontend_release_artifacts_object_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_artifacts
    ADD CONSTRAINT frontend_release_artifacts_object_fk FOREIGN KEY (sha256) REFERENCES public.frontend_release_objects(sha256) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: frontend_release_artifacts frontend_release_artifacts_release_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_artifacts
    ADD CONSTRAINT frontend_release_artifacts_release_fk FOREIGN KEY (release_publication_id, release_id) REFERENCES public.frontend_release_publications(publication_id, release_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_catalog_bindings frontend_release_catalog_bindings_generation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_bindings
    ADD CONSTRAINT frontend_release_catalog_bindings_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.frontend_release_catalog_generations(generation_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_catalog_generations frontend_release_catalog_generations_catalog_publication_id_fke; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_generations
    ADD CONSTRAINT frontend_release_catalog_generations_catalog_publication_id_fke FOREIGN KEY (catalog_publication_id) REFERENCES public.frontend_release_catalog_publications(publication_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_catalog_generations frontend_release_catalog_generations_predecessor_catalog_public; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_catalog_generations
    ADD CONSTRAINT frontend_release_catalog_generations_predecessor_catalog_public FOREIGN KEY (predecessor_catalog_publication_id) REFERENCES public.frontend_release_catalog_publications(publication_id) ON DELETE RESTRICT;


--
-- Name: frontend_release_object_chunks frontend_release_object_chunks_object_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_object_chunks
    ADD CONSTRAINT frontend_release_object_chunks_object_fk FOREIGN KEY (sha256) REFERENCES public.frontend_release_objects(sha256) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: frontend_release_staged_object_chunks frontend_release_staged_object_chunks_object_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.frontend_release_staged_object_chunks
    ADD CONSTRAINT frontend_release_staged_object_chunks_object_fk FOREIGN KEY (sha256) REFERENCES public.frontend_release_staged_objects(sha256) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: governed_binding_rules governed_binding_rules_binding_set_row_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_binding_rules
    ADD CONSTRAINT governed_binding_rules_binding_set_row_id_fkey FOREIGN KEY (binding_set_row_id) REFERENCES public.governed_binding_sets(id) ON DELETE CASCADE;


--
-- Name: governed_binding_sets governed_binding_sets_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_binding_sets
    ADD CONSTRAINT governed_binding_sets_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: governed_capability_instances governed_capability_instances_binding_set_row_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_capability_instances
    ADD CONSTRAINT governed_capability_instances_binding_set_row_id_fkey FOREIGN KEY (binding_set_row_id) REFERENCES public.governed_binding_sets(id) ON DELETE CASCADE;


--
-- Name: governed_derived_telemetry_definitions governed_derived_telemetry_definitions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_derived_telemetry_definitions
    ADD CONSTRAINT governed_derived_telemetry_definitions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: governed_limit_definitions governed_limit_definitions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_limit_definitions
    ADD CONSTRAINT governed_limit_definitions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: governed_packet_definition_fields governed_packet_definition_fields_packet_definition_row_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_packet_definition_fields
    ADD CONSTRAINT governed_packet_definition_fields_packet_definition_row_id_fkey FOREIGN KEY (packet_definition_row_id) REFERENCES public.governed_packet_definitions(id) ON DELETE CASCADE;


--
-- Name: governed_packet_definitions governed_packet_definitions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.governed_packet_definitions
    ADD CONSTRAINT governed_packet_definitions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: ground_station_availability_windows ground_station_availability_windows_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ground_station_availability_windows
    ADD CONSTRAINT ground_station_availability_windows_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: ingress_raw_evidence ingress_raw_evidence_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingress_raw_evidence
    ADD CONSTRAINT ingress_raw_evidence_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: managed_action_requests managed_action_requests_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.managed_action_requests
    ADD CONSTRAINT managed_action_requests_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: managed_capability_records managed_capability_records_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.managed_capability_records
    ADD CONSTRAINT managed_capability_records_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: managed_timer_events managed_timer_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.managed_timer_events
    ADD CONSTRAINT managed_timer_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_active_binding_sets mission_active_binding_sets_activation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_active_binding_sets
    ADD CONSTRAINT mission_active_binding_sets_activation_id_fkey FOREIGN KEY (activation_id) REFERENCES public.mission_binding_set_activations(activation_id) ON DELETE CASCADE;


--
-- Name: mission_active_binding_sets mission_active_binding_sets_activation_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_active_binding_sets
    ADD CONSTRAINT mission_active_binding_sets_activation_request_id_fkey FOREIGN KEY (activation_request_id) REFERENCES public.activation_requests(activation_request_id) ON DELETE RESTRICT;


--
-- Name: mission_active_binding_sets mission_active_binding_sets_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_active_binding_sets
    ADD CONSTRAINT mission_active_binding_sets_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_binding_set_activations mission_binding_set_activations_activation_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_binding_set_activations
    ADD CONSTRAINT mission_binding_set_activations_activation_request_id_fkey FOREIGN KEY (activation_request_id) REFERENCES public.activation_requests(activation_request_id) ON DELETE RESTRICT;


--
-- Name: mission_binding_set_activations mission_binding_set_activations_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_binding_set_activations
    ADD CONSTRAINT mission_binding_set_activations_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_change_sets mission_config_change_sets_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_change_sets
    ADD CONSTRAINT mission_config_change_sets_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_changes mission_config_changes_change_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_changes
    ADD CONSTRAINT mission_config_changes_change_set_id_fkey FOREIGN KEY (change_set_id) REFERENCES public.mission_config_change_sets(change_set_id) ON DELETE CASCADE;


--
-- Name: mission_config_changes mission_config_changes_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_changes
    ADD CONSTRAINT mission_config_changes_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_heads mission_config_heads_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_heads
    ADD CONSTRAINT mission_config_heads_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_ops mission_config_ops_change_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_ops
    ADD CONSTRAINT mission_config_ops_change_id_fkey FOREIGN KEY (change_id) REFERENCES public.mission_config_changes(change_id) ON DELETE CASCADE;


--
-- Name: mission_config_ops mission_config_ops_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_ops
    ADD CONSTRAINT mission_config_ops_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_reviews mission_config_reviews_change_set_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_reviews
    ADD CONSTRAINT mission_config_reviews_change_set_id_fkey FOREIGN KEY (change_set_id) REFERENCES public.mission_config_change_sets(change_set_id) ON DELETE RESTRICT;


--
-- Name: mission_config_reviews mission_config_reviews_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_reviews
    ADD CONSTRAINT mission_config_reviews_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_revision_entries mission_config_revision_entries_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_revision_entries
    ADD CONSTRAINT mission_config_revision_entries_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_config_revision_entries mission_config_revision_entries_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_revision_entries
    ADD CONSTRAINT mission_config_revision_entries_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES public.mission_config_revisions(revision_id) ON DELETE CASCADE;


--
-- Name: mission_config_revisions mission_config_revisions_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_config_revisions
    ADD CONSTRAINT mission_config_revisions_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_event_rebuild_runs mission_event_rebuild_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_event_rebuild_runs
    ADD CONSTRAINT mission_event_rebuild_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_events mission_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_events
    ADD CONSTRAINT mission_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_model_composition_layers mission_model_composition_layers_composition_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_composition_layers
    ADD CONSTRAINT mission_model_composition_layers_composition_fkey FOREIGN KEY (organization_id, mission_id, composition_id) REFERENCES public.mission_model_compositions(organization_id, mission_id, composition_id) ON DELETE RESTRICT;


--
-- Name: mission_model_composition_layers mission_model_composition_layers_layer_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_composition_layers
    ADD CONSTRAINT mission_model_composition_layers_layer_fkey FOREIGN KEY (organization_id, mission_id, layer_id) REFERENCES public.mission_model_layers(organization_id, mission_id, layer_id) ON DELETE RESTRICT;


--
-- Name: mission_model_composition_numbers mission_model_composition_numbers_composition_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_composition_numbers
    ADD CONSTRAINT mission_model_composition_numbers_composition_fkey FOREIGN KEY (organization_id, mission_id, composition_id) REFERENCES public.mission_model_compositions(organization_id, mission_id, composition_id) ON DELETE RESTRICT;


--
-- Name: mission_model_diagnostics mission_model_diagnostics_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_diagnostics
    ADD CONSTRAINT mission_model_diagnostics_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES public.mission_model_revisions(revision_id) ON DELETE CASCADE;


--
-- Name: mission_model_effective_revisions mission_model_effective_revisions_composition_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_effective_revisions
    ADD CONSTRAINT mission_model_effective_revisions_composition_fkey FOREIGN KEY (organization_id, mission_id, composition_id) REFERENCES public.mission_model_compositions(organization_id, mission_id, composition_id) ON DELETE RESTRICT;


--
-- Name: mission_model_effective_revisions mission_model_effective_revisions_revision_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_effective_revisions
    ADD CONSTRAINT mission_model_effective_revisions_revision_fkey FOREIGN KEY (organization_id, mission_id, revision_id, compiler_version) REFERENCES public.mission_model_revisions(organization_id, mission_id, revision_id, compiler_version) ON DELETE RESTRICT;


--
-- Name: mission_model_layers mission_model_layers_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_layers
    ADD CONSTRAINT mission_model_layers_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: mission_model_revision_layers mission_model_revision_layers_layer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_revision_layers
    ADD CONSTRAINT mission_model_revision_layers_layer_id_fkey FOREIGN KEY (layer_id) REFERENCES public.mission_model_layers(layer_id) ON DELETE RESTRICT;


--
-- Name: mission_model_revision_layers mission_model_revision_layers_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_revision_layers
    ADD CONSTRAINT mission_model_revision_layers_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES public.mission_model_revisions(revision_id) ON DELETE CASCADE;


--
-- Name: mission_model_revisions mission_model_revisions_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_revisions
    ADD CONSTRAINT mission_model_revisions_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: mission_model_runtime_plans mission_model_runtime_plans_revision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_model_runtime_plans
    ADD CONSTRAINT mission_model_runtime_plans_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES public.mission_model_revisions(revision_id) ON DELETE CASCADE;


--
-- Name: mission_providers mission_providers_account_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_providers
    ADD CONSTRAINT mission_providers_account_version_fk FOREIGN KEY (organization_id, provider_account_id, provider_account_version) REFERENCES public.provider_account_versions(organization_id, provider_account_id, version);


--
-- Name: mission_providers mission_providers_grant_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_providers
    ADD CONSTRAINT mission_providers_grant_version_fk FOREIGN KEY (organization_id, mission_id, provider_account_grant_id, provider_account_grant_version) REFERENCES public.provider_account_grants(organization_id, mission_id, provider_account_grant_id, version);


--
-- Name: mission_providers mission_providers_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_providers
    ADD CONSTRAINT mission_providers_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_source_endpoints mission_source_endpoints_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_source_endpoints
    ADD CONSTRAINT mission_source_endpoints_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_source_endpoints mission_source_endpoints_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_source_endpoints
    ADD CONSTRAINT mission_source_endpoints_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id);


--
-- Name: mission_spacecraft mission_spacecraft_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_spacecraft
    ADD CONSTRAINT mission_spacecraft_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: mission_spacecraft_types mission_spacecraft_types_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mission_spacecraft_types
    ADD CONSTRAINT mission_spacecraft_types_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: missions missions_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.missions
    ADD CONSTRAINT missions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: ops_dashboards ops_dashboards_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_dashboards
    ADD CONSTRAINT ops_dashboards_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: organization_invitations organization_invitations_accepted_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_invitations
    ADD CONSTRAINT organization_invitations_accepted_by_user_id_fkey FOREIGN KEY (accepted_by_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: organization_invitations organization_invitations_invited_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_invitations
    ADD CONSTRAINT organization_invitations_invited_by_user_id_fkey FOREIGN KEY (invited_by_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: organization_invitations organization_invitations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_invitations
    ADD CONSTRAINT organization_invitations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id) ON DELETE CASCADE;


--
-- Name: organization_memberships organization_memberships_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id) ON DELETE CASCADE;


--
-- Name: organization_memberships organization_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: protocol_anomalies protocol_anomalies_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_anomalies
    ADD CONSTRAINT protocol_anomalies_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: protocol_archive_record_identities protocol_archive_record_identities_segment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_archive_record_identities
    ADD CONSTRAINT protocol_archive_record_identities_segment_id_fkey FOREIGN KEY (segment_id) REFERENCES public.protocol_archive_segments(id) ON DELETE CASCADE;


--
-- Name: protocol_packet_records protocol_packet_records_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_packet_records
    ADD CONSTRAINT protocol_packet_records_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: protocol_packet_records protocol_packet_records_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_packet_records
    ADD CONSTRAINT protocol_packet_records_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: protocol_transfer_frame_records protocol_transfer_frame_records_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_transfer_frame_records
    ADD CONSTRAINT protocol_transfer_frame_records_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id);


--
-- Name: protocol_transfer_frame_records protocol_transfer_frame_records_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.protocol_transfer_frame_records
    ADD CONSTRAINT protocol_transfer_frame_records_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: provider_account_grants provider_account_grants_account_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_account_grants
    ADD CONSTRAINT provider_account_grants_account_version_fk FOREIGN KEY (organization_id, provider_account_id, provider_account_version) REFERENCES public.provider_account_versions(organization_id, provider_account_id, version);


--
-- Name: provider_account_grants provider_account_grants_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_account_grants
    ADD CONSTRAINT provider_account_grants_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: provider_account_versions provider_account_versions_account_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_account_versions
    ADD CONSTRAINT provider_account_versions_account_fk FOREIGN KEY (organization_id, provider_account_id) REFERENCES public.provider_accounts(organization_id, provider_account_id);


--
-- Name: provider_accounts provider_accounts_org_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_accounts
    ADD CONSTRAINT provider_accounts_org_fk FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: provider_audit_entries provider_audit_entries_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_audit_entries
    ADD CONSTRAINT provider_audit_entries_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: provider_change_approvals provider_change_approvals_change_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_change_approvals
    ADD CONSTRAINT provider_change_approvals_change_fk FOREIGN KEY (provider_reservation_change_id) REFERENCES public.provider_reservation_changes(provider_reservation_change_id);


--
-- Name: provider_event_cursors provider_event_cursors_account_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_event_cursors
    ADD CONSTRAINT provider_event_cursors_account_version_fk FOREIGN KEY (organization_id, provider_account_id, provider_account_version) REFERENCES public.provider_account_versions(organization_id, provider_account_id, version);


--
-- Name: provider_event_inbox provider_event_inbox_account_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_account_version_fk FOREIGN KEY (organization_id, provider_account_id, provider_account_version) REFERENCES public.provider_account_versions(organization_id, provider_account_id, version);


--
-- Name: provider_event_inbox provider_event_inbox_cursor_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_cursor_fk FOREIGN KEY (provider_event_cursor_id) REFERENCES public.provider_event_cursors(provider_event_cursor_id);


--
-- Name: provider_event_inbox provider_event_inbox_evidence_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_evidence_fk FOREIGN KEY (provider_evidence_id) REFERENCES public.provider_evidence(provider_evidence_id);


--
-- Name: provider_reservation_changes provider_reservation_changes_reservation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservation_changes
    ADD CONSTRAINT provider_reservation_changes_reservation_fk FOREIGN KEY (provider_reservation_id) REFERENCES public.provider_reservations(provider_reservation_id);


--
-- Name: provider_reservations provider_reservations_account_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_account_version_fk FOREIGN KEY (organization_id, provider_account_id, provider_account_version) REFERENCES public.provider_account_versions(organization_id, provider_account_id, version);


--
-- Name: provider_reservations provider_reservations_contact_plan_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_contact_plan_fk FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version) REFERENCES public.contact_plan_versions(organization_id, mission_id, contact_plan_id, version);


--
-- Name: provider_reservations provider_reservations_contact_requirement_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_contact_requirement_fk FOREIGN KEY (organization_id, mission_id, contact_requirement_id, contact_requirement_version) REFERENCES public.contact_requirement_versions(organization_id, mission_id, contact_requirement_id, version);


--
-- Name: provider_reservations provider_reservations_grant_version_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_grant_version_fk FOREIGN KEY (organization_id, mission_id, provider_account_grant_id, provider_account_grant_version) REFERENCES public.provider_account_grants(organization_id, mission_id, provider_account_grant_id, version);


--
-- Name: provider_reservations provider_reservations_mission_provider_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_mission_provider_fk FOREIGN KEY (mission_id, provider_id, provider_version) REFERENCES public.mission_providers(mission_id, provider_id, version);


--
-- Name: provider_reservations provider_reservations_opportunity_snapshot_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_opportunity_snapshot_fk FOREIGN KEY (contact_opportunity_snapshot_id) REFERENCES public.contact_opportunity_snapshots(contact_opportunity_snapshot_id);


--
-- Name: provider_reservations provider_reservations_transport_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_reservations
    ADD CONSTRAINT provider_reservations_transport_fk FOREIGN KEY (mission_id, transport_id, transport_version) REFERENCES public.comms_transports(mission_id, transport_id, version);


--
-- Name: realized_contacts realized_contacts_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.realized_contacts
    ADD CONSTRAINT realized_contacts_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: replay_dispatch_decisions replay_dispatch_decisions_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_dispatch_decisions
    ADD CONSTRAINT replay_dispatch_decisions_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: replay_dispatch_decisions replay_dispatch_decisions_replay_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_dispatch_decisions
    ADD CONSTRAINT replay_dispatch_decisions_replay_run_id_fkey FOREIGN KEY (replay_run_id) REFERENCES public.replay_runs(replay_run_id) ON DELETE CASCADE;


--
-- Name: replay_dispatch_work_items replay_dispatch_work_items_dispatch_decision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_dispatch_work_items
    ADD CONSTRAINT replay_dispatch_work_items_dispatch_decision_id_fkey FOREIGN KEY (dispatch_decision_id) REFERENCES public.replay_dispatch_decisions(dispatch_decision_id) ON DELETE CASCADE;


--
-- Name: replay_managed_action_requests replay_managed_action_requests_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_action_requests
    ADD CONSTRAINT replay_managed_action_requests_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: replay_managed_action_requests replay_managed_action_requests_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_action_requests
    ADD CONSTRAINT replay_managed_action_requests_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: replay_managed_action_requests replay_managed_action_requests_replay_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_action_requests
    ADD CONSTRAINT replay_managed_action_requests_replay_run_id_fkey FOREIGN KEY (replay_run_id) REFERENCES public.replay_runs(replay_run_id) ON DELETE CASCADE;


--
-- Name: replay_managed_capability_records replay_managed_capability_records_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_capability_records
    ADD CONSTRAINT replay_managed_capability_records_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: replay_managed_capability_records replay_managed_capability_records_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_capability_records
    ADD CONSTRAINT replay_managed_capability_records_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: replay_managed_capability_records replay_managed_capability_records_replay_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_capability_records
    ADD CONSTRAINT replay_managed_capability_records_replay_run_id_fkey FOREIGN KEY (replay_run_id) REFERENCES public.replay_runs(replay_run_id) ON DELETE CASCADE;


--
-- Name: replay_managed_timer_events replay_managed_timer_events_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_timer_events
    ADD CONSTRAINT replay_managed_timer_events_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: replay_managed_timer_events replay_managed_timer_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_timer_events
    ADD CONSTRAINT replay_managed_timer_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: replay_managed_timer_events replay_managed_timer_events_replay_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_managed_timer_events
    ADD CONSTRAINT replay_managed_timer_events_replay_run_id_fkey FOREIGN KEY (replay_run_id) REFERENCES public.replay_runs(replay_run_id) ON DELETE CASCADE;


--
-- Name: replay_runs replay_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_runs
    ADD CONSTRAINT replay_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: replay_telemetry_samples replay_telemetry_samples_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_telemetry_samples
    ADD CONSTRAINT replay_telemetry_samples_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: replay_telemetry_samples replay_telemetry_samples_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_telemetry_samples
    ADD CONSTRAINT replay_telemetry_samples_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: replay_telemetry_samples replay_telemetry_samples_replay_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.replay_telemetry_samples
    ADD CONSTRAINT replay_telemetry_samples_replay_run_id_fkey FOREIGN KEY (replay_run_id) REFERENCES public.replay_runs(replay_run_id) ON DELETE CASCADE;


--
-- Name: scheduled_contact_revisions scheduled_contact_revisions_change_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_contact_revisions
    ADD CONSTRAINT scheduled_contact_revisions_change_fk FOREIGN KEY (provider_reservation_change_id) REFERENCES public.provider_reservation_changes(provider_reservation_change_id);


--
-- Name: scheduled_contact_revisions scheduled_contact_revisions_contact_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_contact_revisions
    ADD CONSTRAINT scheduled_contact_revisions_contact_fk FOREIGN KEY (scheduled_contact_id) REFERENCES public.scheduled_contacts(scheduled_contact_id);


--
-- Name: scheduled_contacts scheduled_contacts_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_contacts
    ADD CONSTRAINT scheduled_contacts_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: semantic_alarm_acknowledgements semantic_alarm_acknowledgements_transition_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_alarm_acknowledgements
    ADD CONSTRAINT semantic_alarm_acknowledgements_transition_id_fkey FOREIGN KEY (transition_id) REFERENCES public.semantic_alarm_transitions(transition_id) ON DELETE RESTRICT;


--
-- Name: semantic_alarm_transitions semantic_alarm_transitions_evaluation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_alarm_transitions
    ADD CONSTRAINT semantic_alarm_transitions_evaluation_id_fkey FOREIGN KEY (evaluation_id) REFERENCES public.semantic_monitoring_evaluations(evaluation_id) ON DELETE CASCADE;


--
-- Name: semantic_monitoring_evaluations semantic_monitoring_evaluations_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_monitoring_evaluations
    ADD CONSTRAINT semantic_monitoring_evaluations_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: service_identities service_identities_mission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identities
    ADD CONSTRAINT service_identities_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES public.missions(mission_id);


--
-- Name: service_identities service_identities_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identities
    ADD CONSTRAINT service_identities_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: service_identities service_identities_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identities
    ADD CONSTRAINT service_identities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: service_identity_accountables service_identity_accountables_service_identity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_identity_accountables
    ADD CONSTRAINT service_identity_accountables_service_identity_id_fkey FOREIGN KEY (service_identity_id) REFERENCES public.service_identities(service_identity_id) ON DELETE RESTRICT;


--
-- Name: spacecraft_application_bindings spacecraft_application_bindings_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spacecraft_application_bindings
    ADD CONSTRAINT spacecraft_application_bindings_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id) ON DELETE CASCADE;


--
-- Name: spacecraft_config_overrides spacecraft_config_overrides_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spacecraft_config_overrides
    ADD CONSTRAINT spacecraft_config_overrides_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: spacecraft_configuration_revisions spacecraft_configuration_revisions_spacecraft_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spacecraft_configuration_revisions
    ADD CONSTRAINT spacecraft_configuration_revisions_spacecraft_fk FOREIGN KEY (organization_id, mission_id, spacecraft_id) REFERENCES public.mission_spacecraft(organization_id, mission_id, spacecraft_id) ON DELETE CASCADE;


--
-- Name: staged_command_items staged_command_items_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_command_items
    ADD CONSTRAINT staged_command_items_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: staged_command_items staged_command_items_stage_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staged_command_items
    ADD CONSTRAINT staged_command_items_stage_fk FOREIGN KEY (organization_id, mission_id, command_stage_id) REFERENCES public.command_stages(organization_id, mission_id, command_stage_id);


--
-- Name: telemetry_latest_limit_state_rebuild_runs telemetry_latest_limit_state_rebuild_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_limit_state_rebuild_runs
    ADD CONSTRAINT telemetry_latest_limit_state_rebuild_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_latest_limit_states telemetry_latest_limit_states_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_limit_states
    ADD CONSTRAINT telemetry_latest_limit_states_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_latest_value_rebuild_runs telemetry_latest_value_rebuild_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_value_rebuild_runs
    ADD CONSTRAINT telemetry_latest_value_rebuild_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_latest_values telemetry_latest_values_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_values
    ADD CONSTRAINT telemetry_latest_values_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: telemetry_latest_values telemetry_latest_values_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_values
    ADD CONSTRAINT telemetry_latest_values_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_latest_values telemetry_latest_values_packet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_latest_values
    ADD CONSTRAINT telemetry_latest_values_packet_id_fkey FOREIGN KEY (packet_id) REFERENCES public.protocol_packet_records(packet_id) ON DELETE CASCADE;


--
-- Name: telemetry_limit_evaluation_runs telemetry_limit_evaluation_runs_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_limit_evaluation_runs
    ADD CONSTRAINT telemetry_limit_evaluation_runs_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_limit_events telemetry_limit_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_limit_events
    ADD CONSTRAINT telemetry_limit_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_samples telemetry_samples_evidence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_samples
    ADD CONSTRAINT telemetry_samples_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES public.ingress_raw_evidence(evidence_id) ON DELETE CASCADE;


--
-- Name: telemetry_samples telemetry_samples_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_samples
    ADD CONSTRAINT telemetry_samples_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: telemetry_samples telemetry_samples_packet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_samples
    ADD CONSTRAINT telemetry_samples_packet_id_fkey FOREIGN KEY (packet_id) REFERENCES public.protocol_packet_records(packet_id) ON DELETE CASCADE;


--
-- Name: transport_action_requests transport_action_requests_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_action_requests
    ADD CONSTRAINT transport_action_requests_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: transport_capability_records transport_capability_records_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_capability_records
    ADD CONSTRAINT transport_capability_records_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: transport_timer_events transport_timer_events_org_mission_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transport_timer_events
    ADD CONSTRAINT transport_timer_events_org_mission_fk FOREIGN KEY (organization_id, mission_id) REFERENCES public.missions(organization_id, mission_id);


--
-- Name: user_local_credentials user_local_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_local_credentials
    ADD CONSTRAINT user_local_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: user_session_tokens user_session_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_session_tokens
    ADD CONSTRAINT user_session_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


-- The only reference row in a freshly migrated, otherwise empty database.
INSERT INTO public.frontend_release_activation_controls (control_id, cutover_epoch, cutover_at, legacy_catalog_publication_id) VALUES (1, 0, NULL, NULL);


--
-- PostgreSQL database dump complete
--
