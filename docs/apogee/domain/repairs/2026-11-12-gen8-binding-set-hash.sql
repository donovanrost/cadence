-- #65 gen 8 repair (domain), run only with director's OK and qa's go, after 00:30Z.
-- Gen 8's stored binding_set_content_sha256 was computed over the in-memory binding set,
-- whose FieldDefinitions carry parameter_id/qualified_name that governed packet definitions
-- don't persist. Read back, v3 hashes to 4edf93da…; correct the three records to that
-- (activation, active binding set, and the approved activation request, which
-- ApprovalAdmission compares; api-ops review). Gen 8 has no activation_executions row.
\set ON_ERROR_STOP on
BEGIN;

-- Precheck: exactly one row each, for this mission, generation 8, the old hash.
DO $$
DECLARE a int; b int; c int;
BEGIN
  SELECT count(*) INTO a FROM mission_binding_set_activations
   WHERE mission_id = 'mission-earendil-demo' AND generation = 8
     AND activation_id = 'activation_ccxol52jpu_17V1V'
     AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';
  SELECT count(*) INTO b FROM mission_active_binding_sets
   WHERE mission_id = 'mission-earendil-demo' AND generation = 8
     AND activation_id = 'activation_ccxol52jpu_17V1V'
     AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';
  SELECT count(*) INTO c FROM activation_requests
   WHERE mission_id = 'mission-earendil-demo'
     AND activation_request_id = 'activation_request_ccxol52jpu_17QMA'
     AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';
  IF a <> 1 OR b <> 1 OR c <> 1 THEN
    RAISE EXCEPTION 'precheck failed: activations=% active=% requests=%', a, b, c;
  END IF;
END $$;

UPDATE mission_binding_set_activations
   SET binding_set_content_sha256 = '4edf93da0468094db3c6f67f78641688b92cb5062157ade2dc5ed3fda01bd093'
 WHERE mission_id = 'mission-earendil-demo' AND generation = 8
   AND activation_id = 'activation_ccxol52jpu_17V1V'
   AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';

UPDATE mission_active_binding_sets
   SET binding_set_content_sha256 = '4edf93da0468094db3c6f67f78641688b92cb5062157ade2dc5ed3fda01bd093'
 WHERE mission_id = 'mission-earendil-demo' AND generation = 8
   AND activation_id = 'activation_ccxol52jpu_17V1V'
   AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';

UPDATE activation_requests
   SET binding_set_content_sha256 = '4edf93da0468094db3c6f67f78641688b92cb5062157ade2dc5ed3fda01bd093'
 WHERE mission_id = 'mission-earendil-demo'
   AND activation_request_id = 'activation_request_ccxol52jpu_17QMA'
   AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';

SELECT 'activations' AS t, generation, binding_set_content_sha256 FROM mission_binding_set_activations
 WHERE mission_id = 'mission-earendil-demo' AND generation = 8
UNION ALL
SELECT 'active', generation, binding_set_content_sha256 FROM mission_active_binding_sets
 WHERE mission_id = 'mission-earendil-demo'
UNION ALL
SELECT 'request', binding_set_version, binding_set_content_sha256 FROM activation_requests
 WHERE activation_request_id = 'activation_request_ccxol52jpu_17QMA';

COMMIT;
