# Appended only to the lab image's release configuration. The normal production
# release retains its external-secret requirement.
if System.get_env("CADENCE_CHAOS_LAB") == "true" and
     System.get_env("POD_NAMESPACE") == "cadence-chaos" do
  config :cadence, :provider_local_credentials, enabled: true
  config :logger, level: :info

  config :cadence_web, CadenceWeb.Endpoint,
    check_origin: [
      "http://cadence.cadence-chaos.svc.cluster.local:4001",
      "http://localhost:14001"
    ]
end
