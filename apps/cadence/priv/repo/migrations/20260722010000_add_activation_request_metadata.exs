defmodule Cadence.Repo.Migrations.AddActivationRequestMetadata do
  use Ecto.Migration

  def change do
    alter table(:activation_requests) do
      add(:metadata, :map, null: false, default: %{})
    end
  end
end
