# Adds contact planning (active fleet planning policy + recurring downlink
# templates) to an existing Earendil seed. Idempotent. Run from apps/cadence:
#   mise exec -- mix run --no-start ../../dev/reflect_orbital_planning.exs
Code.require_file("reflect_orbital/fixture.exs", __DIR__)
Code.require_file("reflect_orbital/planning.exs", __DIR__)
Cadence.Dev.ReflectOrbital.Planning.run()
