defmodule HedwigMopidy do
  @moduledoc """
  """
  
  use Application
  alias Mopidy.{Track,TlTrack,SearchResults,Ref,Library,Tracklist,Playback,Playlists,Playlist,Mixer}
  
  def init(default_options) do
    IO.puts "initializing plug"
    default_options
  end

  def call(conn, _options) do
    IO.puts "calling plug"
    conn
  end

  def run_cowboy_plug do
    { :ok, _ } = Plug.Adapters.Cowboy.http HedwigMopidy.Router, []
   end

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    Supervisor.start_link([worker(__MODULE__, [], function: :run_cowboy_plug)], [strategy: :one_for_one, name: HedwigMopidy.Supervisor])
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

  def rejects_playlist do
    Application.get_env(:hedwig_mopidy, :rejects_playlist) || "spotify:user:labzeroinnovations:playlist:5hJ09W4UOXj3gFndMi2egk"
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
  
  defmodule Thumb do
    defstruct [:user, :track, :playlist, :direction, :timestamp]
  end

  defmodule ThumbStore do

    defp storage do
      HedwigBrain.brain.get_lobe("thumbs")
    end

    def store(%Thumb{} = data, name) do
      HedwigBrain.brain.put(storage(), canonicalize(name), data)
      data
    end

    def retrieve(name) do
      case HedwigBrain.brain.get(storage(), canonicalize(name)) do
        nil -> %Thumb{}
        data -> data
      end
    end

    def all do
      HedwigBrain.brain.all(storage())
    end

    def increment(name) do
      name = canonicalize(name)
      count = case HedwigBrain.brain.get(storage(), name) do
        nil -> 0
        data -> data
      end
      count = count + 1
      HedwigBrain.brain.put(storage(), name, count)
      count
    end

    def decrement(name) do
      name = canonicalize(name)
      count = case HedwigBrain.brain.get(storage(), name) do
        nil -> 0
        data -> data
      end
      count = count - 1
      HedwigBrain.brain.put(storage(), name, count)
      count
    end

    def count(name) do
      case HedwigBrain.brain.get(storage(), canonicalize(name)) do
        nil -> 0
        data -> data
      end
    end

    def canonicalize(string) do
      string
      |> String.trim
    end
  end

  defmodule CurrentPlaylistStore do
    defp storage do
      HedwigBrain.brain.get_lobe("playlist")
    end

    def store(%Playlist{} = playlist) do
      HedwigBrain.brain.put(storage(), "current_playlist", playlist)
      playlist
    end

    def retrieve do
      case HedwigBrain.brain.get(storage(), "current_playlist") do
        {:ok, playlist} -> playlist
        playlist -> playlist
      end
    end

    def all do
      HedwigBrain.brain.all(storage())
    end
  end
  
  def next do  
    current_playlist = CurrentPlaylistStore.retrieve
    with {:ok, %TlTrack{} = next_track} <- Tracklist.next_track do
      HedwigMopidy.notice_message("Up next: #{HedwigMopidy.playing_string(next_track, current_playlist)}")
    else
      {:error, error_message} -> error_message
      _ -> HedwigMopidy.notice_message("No more songs are queued")
    end
  end

  def playlists do
    with {:ok, playlists} <- Playlists.as_list do
      Enum.map_join(playlists, "\n", fn r -> "#{r.name}: #{r.uri}" end)
    end
  end

  def start(playlist) do
    playlist = case playlist do
      "" -> last_playlist()
      _ -> Playlists.lookup(playlist)
    end

    case playlist do
      {:ok, nil} -> "Couldn't find that playlist"
      {:ok, playlist} -> start_playlist(playlist)
      {:error, err} -> "Couldn't load playlist, `#{err}`"
    end
  end
  
  def last_playlist() do
    previous_playlist = CurrentPlaylistStore.retrieve
    case previous_playlist do
      nil -> Playlists.lookup(HedwigMopidy.default_playlist)
        _ -> {:ok, previous_playlist}
    end
  end

  def start_playlist(playlist) do
    with  {:ok, :success} <- Tracklist.clear,
          {:ok, playlist_refs} <- Playlists.get_items(playlist.uri),
          {:ok, tracks} when is_list(tracks) <- add_tracks_in_batches(playlist_refs),
          {:ok, :success} <- Tracklist.set_random(true),
          {:ok, :success} <- Tracklist.set_consume(true), #removes songs from the tracklist after they're played
          {:ok, :success} <- Playback.play do
      "Shuffling #{CurrentPlaylistStore.store(playlist).name}"
    else
      {:error, error_message} -> "Received an error from Mopidy: `#{error_message}`"
      _ ->
        case Tracklist.get_length do
          {:ok, 0} -> HedwigMopidy.error_message("Could find any music on the playlist")
          _        -> HedwigMopidy.error_message("Couldn't find the playlist")
        end
    end
  end

  def stop() do
    with {:ok, :success} <- Playback.pause,
          {:ok, state} <- Playback.get_state,
          {:ok, current_track} <- Playback.get_current_track do
      case state do
        "playing" -> HedwigMopidy.playing_string(current_track, CurrentPlaylistStore.retrieve)
        "stopped" -> HedwigMopidy.notice_message("Stopped")
        "paused"  -> HedwigMopidy.notice_message("Paused " <> HedwigMopidy.track_string(current_track))
        _ -> HedwigMopidy.error_message("Couldn't pause music")
      end
    else
      {:error, error_message} -> error_message
      _ -> HedwigMopidy.error_message("Couldn't pause music")
    end
  end

  def resume do
    with {:ok, :success} <- Playback.play do
      HedwigMopidy.playing_string(HedwigMopidy.currently_playing, CurrentPlaylistStore.retrieve)
    else
      {:error, error_message} -> error_message
      _ -> HedwigMopidy.error_message("Couldn't play music")
    end
  end

  def info do
    HedwigMopidy.playing_string(HedwigMopidy.currently_playing, CurrentPlaylistStore.retrieve)
  end

  def upvote(user) do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    with {:ok, "playing"} <- Playback.get_state do
      if ThumbStore.increment("#{currently_playing.uri}|#{current_playlist.uri}") > 2 do
        Spotify.remove_track_from_playlist(HedwigMopidy.favorites_playlist, currently_playing.uri)
        Spotify.add_track_to_playlist(HedwigMopidy.favorites_playlist, currently_playing.uri)
      end
      ThumbStore.store(%Thumb{user: user,
                              track: currently_playing,
                              playlist: current_playlist,
                              direction: 1,
                              timestamp: :calendar.universal_time()},
                      "#{user}|#{currently_playing.uri}|#{current_playlist.uri}")
      HedwigMopidy.notice_message("Recorded your vote for #{HedwigMopidy.playing_string(currently_playing, current_playlist)} — Thanks!")
    else
      _ -> HedwigMopidy.notice_message(HedwigMopidy.playing_string(currently_playing, current_playlist))
    end
  end

  def downvote(user) do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    with {:ok, %TlTrack{}} <- Tracklist.next_track,
          {:ok, :success} <- Playback.next do
      if ThumbStore.decrement("#{currently_playing.uri}|#{current_playlist.uri}") < -2 do
        Spotify.remove_track_from_playlist(current_playlist.uri, currently_playing.uri)
        Spotify.remove_track_from_playlist(HedwigMopidy.rejects_playlist, currently_playing.uri)
        Spotify.add_track_to_playlist(HedwigMopidy.rejects_playlist, currently_playing.uri)          
      end
      ThumbStore.store(%Thumb{user: user,
                              track: currently_playing,
                              playlist: current_playlist,
                              direction: -1,
                              timestamp: :calendar.universal_time()},
                      "#{user}|#{currently_playing.uri}|#{current_playlist.uri}")
      HedwigMopidy.notice_message("Recorded your vote against #{HedwigMopidy.playing_string(currently_playing, current_playlist)} — Skipping...")
    else
      {:error, error_message} -> error_message
      _ -> HedwigMopidy.notice_message("No more songs are queued")
    end
  end

  def skip do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    with {:ok, :success} <- Playback.next do
      HedwigMopidy.notice_message("Skipping track (without downvoting): #{HedwigMopidy.playing_string(currently_playing, current_playlist)}")
    else
      {:error, error_message} -> error_message
      _ -> HedwigMopidy.notice_message("No more songs are queued")
    end
  end

  def bound_volume(level) do
    max(min(level, 10), 0)
  end

  def volume do
    with {:ok, level} <- Mixer.get_volume do
      "The volume level is set to #{round(level/10)}"
    end
  end

  def change_volume(new_level, absolutely \\ true) do
    with {new_level, _remainder} <- Integer.parse(new_level),
         {:ok, existing_level} <- Mixer.get_volume,
         {:ok, true} <- Mixer.set_volume(bound_volume(if (absolutely), do: new_level, else: new_level + round(existing_level/10)) * 10),
         {:ok, new_level} <- Mixer.get_volume do
      "Changed the volume from #{round(existing_level/10)} to #{round(new_level/10)}"
    end
  end

  def add_tracks_in_batches(tracks, batch_size \\ 100) do
    tracks
    |> Enum.chunk(batch_size, batch_size, [])
    |> Enum.each(fn batch -> Tracklist.add(batch |> Enum.map(fn(%Ref{} = r) -> r.uri end)) end)
    {:ok, tracks}
  end
end

