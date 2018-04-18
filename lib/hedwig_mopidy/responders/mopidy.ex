defmodule HedwigMopidy.Responders.Mopidy do
  use Hedwig.Responder
  
  alias HedwigMopidy.CurrentPlaylistStore
  alias Mopidy.{Library,Tracklist,Playback,Playlists,Playlist,Mixer}
  alias Mopidy.{Track,TlTrack,SearchResult,Ref}
  alias HedwigMopidy.Spotify
  alias HedwigMopidy.Thumb
  alias HedwigMopidy.Thumbstore

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
    send message, HedwigMopidy.playlists
  end

  hear ~r/^dj\sstart(?:\s\<(?<playlist>.*)\>\s*)?/i, message do
    send message, "Loading playlist..."
    send message, HedwigMopidy.start(String.trim(message.matches["playlist"]))
  end

  hear ~r/^dj\s(pause|stop)$/i, message do
    send message, HedwigMopidy.stop
  end

  hear ~r/^dj\s(play|resume)$/i, message do
    send message, HedwigMopidy.resume
  end

  hear ~r/^dj (\?|(what|who)(['\x{2019}]?s| is) (playing|this( (crap|shit|garbage|noise|lovely music)))\??)$/iu, message do
    send message, HedwigMopidy.playing_string(HedwigMopidy.currently_playing, CurrentPlaylistStore.retrieve)
  end

  hear ~r/^dj\s(\+1|:+1:|:thumbsup:|:thumbsup_all:|:metal:|:shaka:|up|yes)$/i, message do
    send message, HedwigMopidy.upvote(HedwigMopidy.user(message))
  end

  hear ~r/^dj\s(\-1|:-1:|:thumbsdown:|:thumbsdown_all:|down|no|gong)$/i, message do
    send message, HedwigMopidy.downvote(HedwigMopidy.user(message))
  end

  hear ~r/^dj\s(skip|next)$/i, message do
    send message, HedwigMopidy.skip
  end

  hear ~r/^dj\s(what|who)['\x{2019}]?s (next|up next|on deck|downstream)\??$/iu, message do
    send message, HedwigMopidy.info
  end

  hear ~r/^dj\svol(ume)?$/i, message do
    send message, HedwigMopidy.volume
  end

  hear ~r/^dj\svol(ume)?\s(?<level>.*)$/i, message do
    level = String.downcase(message.matches["level"])
    response = cond do
      Enum.member?(["up", "more", "moar", "+", "++", "+1"], level) -> HedwigMopidy.change_volume("1", false)
      Enum.member?(["down", "less", "-", "--", "-1"], level) -> HedwigMopidy.change_volume("-1", false)
      true -> HedwigMopidy.change_volume(message.matches["level"])
    end
    send message, response
  end
  
  hear ~r/^dj\scrank\sit.*$/i, message do
    send message, HedwigMopidy.change_volume("3", false)
  end

  #experimental
  hear ~r/^dj\splay\sartist\s(?<artist>.*)$/i, message do
    artist = message.matches["artist"]
    response =
      with {:ok, %SearchResult{} = search_results} <- Library.search(%{artist: [artist]}),
           {:ok, :success} <- Tracklist.clear,
           {:ok, tracks} when is_list(tracks) <- HedwigMopidy.add_tracks_in_batches(search_results.tracks),
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
           {:ok, tracks} when is_list(tracks) <- HedwigMopidy.add_tracks_in_batches(search_results.tracks),
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

  def terminate(_reason, _state) do
    #no-op
  end
end