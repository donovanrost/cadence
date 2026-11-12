-- #65 gen 8 repair (domain), run only with director's OK and qa's go, after 00:30Z.
-- Gen 8's stored binding_set_content_sha256 was computed over the in-memory binding set,
-- whose FieldDefinitions carry parameter_id/qualified_name that governed packet definitions
-- don't persist. Read back, v3 hashes to 4edf93da…; correct the two records to that.
\set ON_ERROR_STOP on
BEGIN;

-- Precheck: exactly one row each, for this mission, generation 8, the old hash.
DO $$
DECLARE a int; b int;
BEGIN
  SELECT count(*) INTO a FROM mission_binding_set_activations
   WHERE mission_id = 'mission-earendil-demo' AND generation = 8
     AND activation_id = 'activation_ccxol52jpu_17V1V'
     AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';
  SELECT count(*) INTO b FROM mission_active_binding_sets
   WHERE mission_id = 'mission-earendil-demo' AND generation = 8
     AND activation_id = 'activation_ccxol52jpu_17V1V'
     AND binding_set_content_sha256 = 'fa87fa89ce3eaef6952c548315799df0eeedcf42ac2c0448c954c85789a6ae9c';
  IF a <> 1 OR b <> 1 THEN
    RAISE EXCEPTION 'precheck failed: activations=% active=%', a, b;
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

SELECT 'activations' AS t, generation, binding_set_content_sha256 FROM mission_binding_set_activations
 WHERE mission_id = 'mission-earendil-demo' AND generation = 8
UNION ALL
SELECT 'active', generation, binding_set_content_sha256 FROM mission_active_binding_sets
 WHERE mission_id = 'mission-earendil-demo';

COMMIT;
