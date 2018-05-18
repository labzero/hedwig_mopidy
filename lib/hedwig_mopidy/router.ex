defmodule HedwigMopidy.Router do
  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger
  end
  plug :match
  plug :dispatch

  get "/" do
    send_resp(conn, 200, "Hedwig Mopidy API")
  end

  get "/favicon.ico" do
    send_resp(conn, 200, '')
  end

  get "/info" do
    send_resp(conn, 200, HedwigMopidy.info)
  end
  
  put "/start" do
    send_resp(conn, 200, HedwigMopidy.resume)
  end

  put "/stop" do
    send_resp(conn, 200, HedwigMopidy.stop)
  end

  put "/skip" do
    send_resp(conn, 200, HedwigMopidy.skip)
  end
  
  put "/vote/:user/:direction" do
    cond do
      Enum.member?([1, "up", "yes"], direction) ->
        send_resp(conn, 200, HedwigMopidy.upvote(user))
      Enum.member?([-1, "down", "no", "gong"], direction) ->
        send_resp(conn, 200, HedwigMopidy.downvote(user))
      true ->
        send_resp(conn, 500, "Direction #{direction} is not supported. Supported values are: up/down, 1/-1, yes/no, and gong")
    end
  end

  get "/volume" do
    send_resp(conn, 200, HedwigMopidy.volume)
  end

  put "/volume/:level" do
    send_resp(conn, 200, HedwigMopidy.change_volume(level, true))
  end
  
  post "/volume/:increment" do
    send_resp(conn, 200, HedwigMopidy.change_volume(increment, false))
  end
end