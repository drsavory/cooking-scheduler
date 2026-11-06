defmodule CookingScheduler.Repo do
  use Ecto.Repo,
    otp_app: :cooking_scheduler,
    adapter: Ecto.Adapters.Postgres
end
