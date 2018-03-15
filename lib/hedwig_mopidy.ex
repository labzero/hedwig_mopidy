defmodule HedwigMopidy do
  use Application

  alias Mopidy.{Track,TlTrack,Playback,Playlist}

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

  def default_playlist do
    Application.get_env(:hedwig_mopidy, :default_playlist) || "spotify:user:labzeroinnovations:playlist:64mMWs2NiiguFZWtODm6Jh"
  end

  def favorites_playlist do
    Application.get_env(:hedwig_mopidy, :favorites_playlist) || "spotify:user:labzeroinnovations:playlist:00l7ibuNDlOGRvfReyaUge"
  end

  defmodule Spotify do

    def get_authorization_code(code) do
      {:ok, response} = HTTPoison.post("https://accounts.spotify.com/api/token",
                                       "grant_type=authorization_code&code=#{code}",
                                       ["Authorization": "Basic #{:base64.encode(get_secrets())}",
                                        "Content-Type": "application/x-www-form-urlencoded"],
                                       hackney: [pool: :tracklist])
      Poison.decode!(response.body)
    end

    def get_token do
      {:ok, response} = HTTPoison.post("https://accounts.spotify.com/api/token",
                                       "grant_type=refresh_token&refresh_token=#{get_refresh_token()}",
                                       ["Authorization": "Basic #{:base64.encode(get_secrets())}",
                                        "Content-Type": "application/x-www-form-urlencoded"],
                                       hackney: [pool: :tracklist])
      Poison.decode!(response.body)["access_token"]
    end

    def add_track_to_playlist(playlist_uri, track_uri) do
      api_url = transform_playlist_uri(playlist_uri)
      {:ok, response} = HTTPoison.post("#{api_url}?uris=#{track_uri}",
                                       "",
                                       ["Authorization": "Bearer #{get_token()}",
                                        "Accept": "application/json"],
                                       hackney: [pool: :tracklist])
      Poison.decode!(response.body)
    end

    def remove_track_from_playlist(playlist_uri, track_uri) do
      api_url = transform_playlist_uri(playlist_uri)
      {:ok, response} = HTTPoison.request(:delete,
                                           api_url,
                                           "{\"tracks\":[{\"uri\":\"#{track_uri}\"}]}",
                                           ["Authorization": "Bearer #{get_token()}", "Content-Type": "application/json"],
                                           hackney: [pool: :tracklist])
      Poison.decode!(response.body)
    end

    def transform_playlist_uri(uri) do
      playlist_tokens = Regex.named_captures(~r/^spotify:user:(?<user>.*):playlist:(?<playlist>.*)$/, uri)
      user = playlist_tokens["user"]
      playlist = playlist_tokens["playlist"]
      "https://api.spotify.com/v1/users/#{user}/playlists/#{playlist}/tracks"
    end

    def get_secrets do
      client_id = System.get_env("SPOTIFY_CLIENT_ID")
      client_secret = System.get_env("SPOTIFY_CLIENT_SECRET")
      if client_id && client_secret do
        "#{client_id}:#{client_secret}"
      else
        nil
      end
    end

    def get_refresh_token do
      System.get_env("SPOTIFY_REFRESH_TOKEN")
    end
  end
end