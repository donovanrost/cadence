defmodule Cadence.Repo do
  use Ecto.Repo,
    otp_app: :cadence,
    adapter: Ecto.Adapters.Postgres
end
