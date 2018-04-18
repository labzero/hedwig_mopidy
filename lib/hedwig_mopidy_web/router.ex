defmodule HedwigMopidyWeb.Router do
  use HedwigMopidyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HedwigMopidyWeb do
    pipe_through :browser
    get "/", PageController, :index
  end

  scope "/api", HedwigMopidyWeb do
    pipe_through :api
    get "/", APIController, :index
    get "/info", APIController, :info
    get "/start", APIController, :start #testing
    put "/start", APIController, :start
    get "/stop", APIController, :stop #testing
    put "/stop", APIController, :stop
    get "/skip", APIController, :skip #testing
    put "/skip", APIController, :skip
    get "/vote", APIController, :vote #testing
    put "/vote", APIController, :vote
    get "/volume", APIController, :volume
    put "/volume", APIController, :reset_volume
    post "/volume", APIController, :change_volume
  end
end