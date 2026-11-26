defmodule Cadence.Repo.Migrations.DropRedundantCommandScopeIndexes do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE command_requests DROP CONSTRAINT command_requests_scope_idx_uniq",
      "ALTER TABLE command_requests ADD CONSTRAINT command_requests_scope_idx_uniq UNIQUE (mission_id, command_request_id)"
    )

    execute(
      "ALTER TABLE command_stages DROP CONSTRAINT command_stages_scope_idx_uniq",
      "ALTER TABLE command_stages ADD CONSTRAINT command_stages_scope_idx_uniq UNIQUE (mission_id, command_stage_id)"
    )

    execute(
      "ALTER TABLE staged_command_items DROP CONSTRAINT staged_command_items_scope_idx_uniq",
      "ALTER TABLE staged_command_items ADD CONSTRAINT staged_command_items_scope_idx_uniq UNIQUE (mission_id, staged_command_item_id)"
    )
  end
end
