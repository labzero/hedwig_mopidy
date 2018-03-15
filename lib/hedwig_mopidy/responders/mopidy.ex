defmodule HedwigMopidy.Responders.Mopidy do
  use Hedwig.Responder

  alias Mopidy.{Library,Tracklist,Playback,Playlists,Playlist,Mixer}
  alias Mopidy.{Track,TlTrack,SearchResult,Ref}
  alias HedwigMopidy.Spotify

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

  @usage """
  `dj playlists` lists all the available playlists
  `dj start` shuffles the last-played playlist, or Lab Zero default playlist
  `dj start <uri>` shuffles a publicly-available playlist
  `dj pause|stop` ceases playback
  `dj play|resume` starts playback
  `dj ?` or `who's playing` or `what's playing`, shows current track and playlist
  `dj who's next` or `what's next`, shows upcoming track and playlist
  `dj +1|up|yes` upvotes the currently playing track
  `dj -1|down|no|gong` downvotes the currently playing track and skips to the next
  `dj skip|next` skips to the next track without the fanfare
  `dj volume` replies with the current volume level (0-10)
  `dj volume up|more|moar|+|++|+1` increases the volume by 1 level
  `dj volume down|less|-|--|-1` decreases the volume by 1 level
  `dj crank it` increases the volume by 3 levels
  """

  hear ~r/^dj\splaylists$/i, message do
    response =
      with {:ok, playlists} <- Playlists.as_list do
        Enum.map_join(playlists, "\n", fn r -> "#{r.name}: #{r.uri}" end)
      end
    send message, response
  end

  hear ~r/^dj\sstart(?:\s\<(?<playlist>.*)\>\s*)?/i, message do
    arg = String.trim(message.matches["playlist"])

    playlist = case arg do
      "" -> last_playlist()
      _ -> Playlists.lookup(arg)
    end

    case playlist do
      {:ok, nil} -> send message, "Couldn't find that playlist"
      {:ok, playlist} -> start_playlist(message, playlist)
      {:error, err} -> send message, "Couldn't load playlist, `#{err}`"
    end
  end

  def last_playlist() do
    previous_playlist = CurrentPlaylistStore.retrieve
    case previous_playlist do
      nil -> Playlists.lookup(HedwigMopidy.default_playlist)
        _ -> {:ok, previous_playlist}
    end
  end

  def start_playlist(message, playlist) do
    send message, "Loading playlist..."
    response =
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
    send message, response
  end

  hear ~r/^dj\s(pause|stop)$/i, message do
    response =
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
    send message, response
  end

  hear ~r/^dj\s(play|resume)$/i, message do
    response =
      with {:ok, :success} <- Playback.play do
        HedwigMopidy.playing_string(HedwigMopidy.currently_playing, CurrentPlaylistStore.retrieve)
      else
        {:error, error_message} -> error_message
        _ -> HedwigMopidy.error_message("Couldn't play music")
      end
    send message, response
  end

  hear ~r/^dj (\?|(what|who)(['\x{2019}]?s| is) (playing|this( (crap|shit|garbage|noise|lovely music)))\??)$/iu, message do
    send message, HedwigMopidy.playing_string(HedwigMopidy.currently_playing, CurrentPlaylistStore.retrieve)
  end

  hear ~r/^dj\s(\+1|:+1:|:thumbsup:|:thumbsup_all:|:metal:|:shaka:|up|yes)$/i, message do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    response =
      with {:ok, "playing"} <- Playback.get_state do
        user = HedwigMopidy.user(message)
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
    send message, response
  end

  hear ~r/^dj\s(\-1|:-1:|:thumbsdown:|:thumbsdown_all:|down|no|gong)$/i, message do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    response =
      with {:ok, %TlTrack{}} <- Tracklist.next_track,
           {:ok, :success} <- Playback.next do
        user = HedwigMopidy.user(message)
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
    send message, response
  end

  hear ~r/^dj\s(skip|next)$/i, message do
    current_playlist = CurrentPlaylistStore.retrieve
    response =
      with {:ok, %TlTrack{} = next_track} <- Tracklist.next_track,
           {:ok, :success} <- Playback.next do
            HedwigMopidy.notice_message("Skipping track (without downvoting): #{HedwigMopidy.playing_string(HedwigMopidy.currently_playing, current_playlist)}")
      else
        {:error, error_message} -> error_message
        _ -> HedwigMopidy.notice_message("No more songs are queued")
      end
    send message, response
  end

  hear ~r/^dj\s(what|who)['\x{2019}]?s (next|up next|on deck|downstream)\??$/iu, message do
    current_playlist = CurrentPlaylistStore.retrieve
    response =
      with {:ok, %TlTrack{} = next_track} <- Tracklist.next_track do
        HedwigMopidy.notice_message("Up next: #{HedwigMopidy.playing_string(next_track, current_playlist)}")
      else
        {:error, error_message} -> error_message
        _ -> HedwigMopidy.notice_message("No more songs are queued")
      end
    send message, response
  end

  hear ~r/^dj\svol(ume)?$/i, message do
    response = with {:ok, level} <- Mixer.get_volume do
      "The volume level is set to #{round(level/10)}"
    end
    send message, response
  end

  hear ~r/^dj\svol(ume)?\s(?<level>.*)$/i, message do
    level = String.downcase(message.matches["level"])
    response = cond do
      Enum.member?(["up", "more", "moar", "+", "++", "+1"], level) -> change_volume("1", false)
      Enum.member?(["down", "less", "-", "--", "-1"], level) -> change_volume("-1", false)
      true -> change_volume(message.matches["level"])
    end
    send message, response
  end

  hear ~r/^dj\scrank\sit.*$/i, message do
    send message, change_volume("3", false)
  end

  def bound_volume(level) do
    max(min(level, 10), 0)
  end

  def change_volume(new_level, absolutely \\ true) do
    with {new_level, _remainder} <- Integer.parse(new_level),
         {:ok, existing_level} <- Mixer.get_volume,
         {:ok, true} <- Mixer.set_volume(bound_volume(new_level = if (absolutely), do: new_level, else: new_level + round(existing_level/10)) * 10),
         {:ok, new_level} <- Mixer.get_volume do
      "Changed the volume from #{round(existing_level/10)} to #{round(new_level/10)}"
    end
  end

  #experimental
  hear ~r/^dj\splay\sartist\s(?<artist>.*)$/i, message do
    artist = message.matches["artist"]

    response =
      with {:ok, %SearchResult{} = search_results} <- Library.search(%{artist: [artist]}),
           {:ok, :success} <- Tracklist.clear,
           {:ok, tracks} when is_list(tracks) <- add_tracks_in_batches(search_results.tracks),
           {:ok, :success} <- Playback.play do
        HedwigMopidy.currently_playing
      else
        {:error, error_message} -> error_message
        _ ->
          case Tracklist.get_length do
            {:ok, 0} -> HedwigMopidy.error_message("Couldn't find any music for that artist")
            _        -> HedwigMopidy.error_message("Couldn't play music by that artist")
          end
      end
    send message, response
  end

  #experimental
  hear ~r/^dj\splay\salbum\s(?<album>.*)\sby\s(?<artist>.*)$/i, message do
    album = message.matches["album"]
    artist = message.matches["artist"]

    response =
      with {:ok, %SearchResult{} = search_results} <- Library.search(%{artist: [artist], album: [album]}),
           {:ok, :success} <- Tracklist.clear,
           {:ok, tracks} when is_list(tracks) <- add_tracks_in_batches(search_results.tracks),
           {:ok, :success} <- Playback.play do
        HedwigMopidy.currently_playing
      else
        {:error, error_message} -> error_message
        _ ->
          case Tracklist.get_length do
            {:ok, 0} -> HedwigMopidy.error_message("Couldn't find any music for that album")
            _        -> HedwigMopidy.error_message("Couldn't play music for that album")
          end
      end

    send message, response
  end

  def add_tracks_in_batches(tracks, batch_size \\ 100) do
    tracks
    |> Enum.chunk(batch_size, batch_size, [])
    |> Enum.each(fn batch -> Tracklist.add(batch |> Enum.map(fn(%Ref{} = r) -> r.uri end)) end)
    {:ok, tracks}
  end

  def terminate(_reason, _state) do
    #no-op
  end
end