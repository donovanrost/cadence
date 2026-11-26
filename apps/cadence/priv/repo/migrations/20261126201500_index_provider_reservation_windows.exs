defmodule Cadence.Repo.Migrations.IndexProviderReservationWindows do
  use Ecto.Migration

  def change do
    create(
      index(
        :provider_reservations,
        [:organization_id, :mission_id, :starts_at, "provider_reservation_id COLLATE \"C\""],
        name: :provider_reservations_window_cursor_idx
      )
    )

    create(
      index(:provider_reservations, [:organization_id, :mission_id, :ends_at],
        name: :provider_reservations_window_end_idx
      )
    )
  end
end
