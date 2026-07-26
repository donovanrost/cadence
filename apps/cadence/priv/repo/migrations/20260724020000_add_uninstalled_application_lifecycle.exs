defmodule Cadence.Repo.Migrations.AddUninstalledApplicationLifecycle do
  use Ecto.Migration

  def up do
    drop(constraint(:application_installations, :application_installations_lifecycle_state_check))

    create(
      constraint(:application_installations, :application_installations_lifecycle_state_check,
        check: "lifecycle_state IN ('installed', 'disabled', 'uninstalled')"
      )
    )

    drop(
      constraint(:application_installation_events, :application_installation_events_type_check)
    )

    create(
      constraint(:application_installation_events, :application_installation_events_type_check,
        check:
          "event_type IN ('installed', 'reinstalled', 'enabled', 'disabled', 'uninstalled', 'application_upgraded', 'configuration_updated')"
      )
    )
  end

  def down do
    execute("""
    UPDATE application_installations
    SET lifecycle_state = 'disabled'
    WHERE lifecycle_state = 'uninstalled'
    """)

    execute("""
    UPDATE application_installation_events
    SET
      event_type = CASE
        WHEN event_type = 'uninstalled' THEN 'disabled'
        WHEN event_type = 'reinstalled' THEN 'enabled'
        ELSE event_type
      END,
      previous_lifecycle_state = CASE
        WHEN previous_lifecycle_state = 'uninstalled' THEN 'disabled'
        ELSE previous_lifecycle_state
      END,
      current_lifecycle_state = CASE
        WHEN current_lifecycle_state = 'uninstalled' THEN 'disabled'
        ELSE current_lifecycle_state
      END
    WHERE
      event_type IN ('uninstalled', 'reinstalled')
      OR previous_lifecycle_state = 'uninstalled'
      OR current_lifecycle_state = 'uninstalled'
    """)

    drop(
      constraint(:application_installation_events, :application_installation_events_type_check)
    )

    create(
      constraint(:application_installation_events, :application_installation_events_type_check,
        check:
          "event_type IN ('installed', 'enabled', 'disabled', 'application_upgraded', 'configuration_updated')"
      )
    )

    drop(constraint(:application_installations, :application_installations_lifecycle_state_check))

    create(
      constraint(:application_installations, :application_installations_lifecycle_state_check,
        check: "lifecycle_state IN ('installed', 'disabled')"
      )
    )
  end
end
