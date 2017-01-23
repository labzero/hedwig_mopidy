defmodule HedwigMopidy.Responders.Mopidy do
  use Hedwig.Responder

  alias Mopidy.{Library,Tracklist,Playback,Playlists,Playlist}
  alias Mopidy.{Track,TlTrack,SearchResult,Ref}

  defmodule Thumb do
    defstruct [:user, :track, :playlist, :direction, :timestamp]
  end

  defmodule ThumbStore do
    defp brain do
      HedwigBrain.brain
    end

    defp storage do
      brain.get_lobe("thumbs")
    end

    def store(%Thumb{} = data, name) do
      brain.put(storage, name, data)
      data
    end

    def retrieve(name) do
      case brain.get(storage, canonicalize(name)) do
        nil -> %Thumb{}
        data -> data
      end
    end

    def all do
      brain.all(storage)
    end

    def canonicalize(string) do
      string
      |> String.downcase
      |> String.trim
    end
  end

  defmodule CurrentPlaylistStore do
    defp brain do
      HedwigBrain.brain
    end

    defp storage do
      brain.get_lobe("playlist")
    end

    def store(%Playlist{} = playlist) do
      brain.put(storage, "current_playlist", playlist)
      playlist
    end

    def retrieve do
      case brain.get(storage, "current_playlist") do
        nil -> %Playlist{name: "any playlist"}
        playlist -> playlist
      end
    end

    def all do
      brain.all(storage)
    end
  end

  @usage """

`dj` displays this message
`dj playlists` lists all the available playlists
`dj start <uri>` shuffles the playlist specified by <uri> (defaults to the Lab Zero playlist)
`dj pause|stop` ceases playback
`dj play|resume` starts playback
`dj (what|who) ('s| is) playing` displays the currently playing track and playlist (e.g. what's playing or who is playing)
`dj +1|:thumbsup:|:thumbsup_all:|:metal:|:shaka:|up|yes` upvotes if you like the currently playing track on the currently playing playlist
`dj -1|:thumbsdown:|:thumbsdown_all:|down|no|skip|next` votes against the currently playing track on the currently playing playlist and skips to the next track
  """

  hear ~r/^dj$/i, message do
    send message, @usage
  end

  hear ~r/^dj\splaylists$/i, message do
    response =
      with {:ok, playlists} <- Playlists.as_list do
        Enum.map_join(playlists, "\n", fn r -> "#{r.name}: #{r.uri}" end)
      end
    send message, response
  end

  hear ~r/^dj\sstart(?:\s(?<playlist>.*)\s*)?/i, message do
    arg = String.strip(message.matches["playlist"])
    playlist =
      if arg == "" do
        previous_playlist = CurrentPlaylistStore.retrieve
        if previous_playlist.uri == nil do
          with {:ok, playlist} <- Playlists.lookup("spotify:user:1241621489:playlist:6MefnARMuplYzfgUgXlfAG") do
            playlist
          end
        else
          previous_playlist
        end
      else
        with {:ok, playlist} <- Playlists.lookup(arg) do
          playlist
        end
      end
    response =
      with  {:ok, :success} <- Tracklist.clear,
            {:ok, playlist_refs} <- Playlists.get_items(playlist.uri),
            {:ok, tracks} when is_list(tracks) <- Tracklist.add(playlist_refs |> Enum.map(fn(%Ref{} = r) -> r.uri end)),
            {:ok, :success} <- Tracklist.set_random(true),
            {:ok, :success} <- Playback.play do
        CurrentPlaylistStore.store(playlist)
        "Shuffling #{playlist.name}"
      else
        {:error, error_message} -> error_message
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

  hear ~r/^dj\s(what|who).*\splaying/i, message do
    send message, HedwigMopidy.playing_string(HedwigMopidy.currently_playing, CurrentPlaylistStore.retrieve)
  end

  hear ~r/^dj\s(\+1|:thumbsup:|:thumbsup_all:|:metal:|:shaka:|up|yes)$/i, message do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    response =
      with {:ok, "playing"} <- Playback.get_state do
        user = HedwigMopidy.user(message)
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

  hear ~r/^dj\s(\-1|:thumbsdown:|:thumbsdown_all:|down|no|skip|next)$/i, message do
    currently_playing = HedwigMopidy.currently_playing
    current_playlist = CurrentPlaylistStore.retrieve
    response =
      with {:ok, %TlTrack{} = next_track} <- Tracklist.next_track,
           {:ok, :success} <- Playback.next do
        user = HedwigMopidy.user(message)
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

  #experimental
  hear ~r/^dj\splay\sartist\s(?<artist>.*)$/i, message do
    artist = message.matches["artist"]

    response =
      with {:ok, %SearchResult{} = search_results} <- Library.search(%{artist: [artist]}),
           {:ok, :success} <- Tracklist.clear,
           {:ok, tracks} when is_list(tracks) <- Tracklist.add(search_results.tracks |> Enum.map(fn(%Track{} = track) -> track.uri end)),
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
           {:ok, tracks} when is_list(tracks) <- Tracklist.add(search_results.tracks |> Enum.map(fn(%Track{} = track) -> track.uri end)),
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

  def terminate(reason, state) do
    #no-op
  end
end