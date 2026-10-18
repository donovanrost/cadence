defmodule Cadence.FrontendReleaseMigrationTestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :cadence,
    adapter: Ecto.Adapters.Postgres
end
