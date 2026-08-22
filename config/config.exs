import Config

# The root project exists only for repository-wide tooling. Reuse the web
# composition's build-time configuration so Mix can validate path dependencies
# while running Workspace, Credo, and aggregate test commands. The root owns no
# runtime configuration and is not a release entry point.
import_config "../apps/cadence_web/config/config.exs"
