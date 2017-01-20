defmodule HedwigMopidy do
  use Application

  alias Mopidy.{Track,TlTrack,Playback,Playlists,Playlist}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    opts = [strategy: :one_for_one, name: HedwigMopidy.Supervisor]
    Supervisor.start_link([], opts)
  end

  def currently_playing do
    with {:ok, "playing"} <- Playback.get_state,
         {:ok, %Track{} = current_track} <- Playback.get_current_track do
      current_track
    else
      {:ok, _} -> %Track{}
      {:error, error_message} -> error_message
      _ -> error_message("Couldn't find what's playing")
    end
  end

  def parse_boolean("off"), do: {"off", false}
  def parse_boolean(_),     do: {"on", true}

  def playing_message(message), do: "♫ " <> to_string(message)
  def notice_message(message), do: "♮ " <> to_string(message)
  def error_message(message), do: "✗ " <> to_string(message)

  def playing_string(%Track{} = track, %Playlist{} = playlist) do
    playing_message("#{HedwigMopidy.track_string(track)} on #{playlist.name}")
  end
  def playing_string(%TlTrack{} = tl_track, %Playlist{} = playlist) do
    playing_string(tl_track.track, playlist)
  end

  def track_string(%Track{} = track) do
    if track.uri do
      "#{track.name} by #{artists_string(track.artists)}"
    else
      "Nothing is playing"
    end
  end
  def track_string(%TlTrack{} = tl_track) do
    track_string(tl_track.track)
  end
  def track_string(_) do
    "No track"
  end

  def artists_string(artists) do
    artists
    |> Enum.map(fn artist -> artist.name end)
    |> Enum.join(", ")
  end

  @doc """
  Gets the Web URL from :hedwig_mopidy, :web_url application env
  Returns binary
  """
  def web_url do
    Application.get_env(:hedwig_mopidy, :web_url)
  end

  @doc """
  Gets the Icecast URL from :hedwig_mopidy, :icecast_url application env
  Returns binary
  """
  def icecast_url do
    Application.get_env(:hedwig_mopidy, :icecast_url)
  end

  def user(message) do
    if is_map(message.user) do message.user.name else message.user end
  end
end
