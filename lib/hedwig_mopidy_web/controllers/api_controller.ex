defmodule HedwigMopidyWeb.APIController do
    use HedwigMopidyWeb, :controller
    alias HedwigMopidy
  
    def index(conn, _params) do
      text conn, "Hedwig Mopidy API"
    end
  
    def info(conn, _params) do
      text conn, HedwigMopidy.info
    end

    def start(conn, _params) do
      text conn, HedwigMopidy.resume
    end

    def stop(conn, _params) do
      text conn, HedwigMopidy.stop
    end

    def skip(conn, _params) do
      text conn, HedwigMopidy.skip
    end

    def vote(conn, %{"user" => name, "up" => up} = _params) do
      if (up) do
        text conn, HedwigMopidy.upvote(name)
      else
        text conn, HedwigMopidy.downvote(name)
      end
    end

    def volume(conn, _params) do
      text conn, HedwigMopidy.volume
    end

    def change_volume(conn, %{"increment" => increment} = _params) do
      text conn, HedwigMopidy.change_volume(increment, false)
    end

    def reset_volume(conn, %{"level" => level} = _params) do
      text conn, HedwigMopidy.change_volume(level, true)
    end
  end