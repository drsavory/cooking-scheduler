defmodule CookingSchedulerWeb.Router do
  use CookingSchedulerWeb, :router

  import CookingSchedulerWeb.Auth, only: [require_password: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CookingSchedulerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The whole site sits behind one shared password (ADR 0015); only logging in is open.
  pipeline :protected do
    plug :require_password
  end

  scope "/", CookingSchedulerWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", CookingSchedulerWeb do
    pipe_through [:browser, :protected]

    live_session :default,
      on_mount: [CookingSchedulerWeb.SearchHook, {CookingSchedulerWeb.Auth, :require_password}] do
      live "/", HomeLive
      live "/setup", SetupLive
      live "/dishes/new", DishFormLive, :new
      live "/dishes/:id", DishLive, :saved
      live "/meals/:meal_id/dishes/:id", DishLive, :meal
      live "/meals/:id/plan", PlanLive
      live "/meals/:id/prep", PrepLive
      live "/meals/:id/shopping", ShoppingLive
      live "/meals/:id/cook", CookLive
      live "/meals/:id/sheet", SheetLive
      live "/meals/:id/summary", SummaryLive
    end
  end

  # Images are requested with an `image/*` Accept header, so no `accepts` plug here.
  pipeline :photos do
    plug :fetch_session
  end

  scope "/", CookingSchedulerWeb do
    pipe_through [:photos, :protected]

    get "/photos/:id", PhotoController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", CookingSchedulerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cooking_scheduler, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CookingSchedulerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
