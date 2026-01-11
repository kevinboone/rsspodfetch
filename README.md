# rsspodfetch.sh

v0.1b, January 2026

## What is this

`rsspodfetch.sh` is a simple Bash script for Linux, which maintains a local
copy of an audio podcast that is defined by an RSS file or stream. That is, it
converts a podcast stream into a locally-stored audiobook, with one 'chapter'
per podcast program. The script works by parsing the RSS file, and downloading
the audio stream for each program to completion, saving the resulting audio
files to a specified directory. It shouldn't attempt to download a file that
already exists in the output directory. The utility can therefore be run as
often as required, and will ensure that the local cache is up to date.

I listen to podcasts offline on my Android phone, using Smart Audiobook Player.
Any audio player should be fine for this purpose, but `rsspodfetch.sh`
specifically writes files that are palatable to Smart Audiobook Player, Listen,
and similar apps. In particular:

- It sets the same 'album' tag identically in each file it writes in a particular
  run, so that files in the
  same podcast get grouped together as part of the same 'book'. 
- It stores each file with a name that contains the program's publication date,
  in a sortable format. It also writes the 'title' tag in a similar way. Smart
  Audiobook Player assumes that tracks should be played in alphanumeric order of
  track title or, if there is no title, in order of filename. This is common
  behaviour for local audio file players, however.

## Why?

I listen to podcasts when I'm working in my woods, where I have no Internet access.
Some proprietary podcast players can maintain a local cache if you ask them
to, but using such a feature requires a measure of forward planning. In addition,
an audiobook player like Smart or Listen has a much nicer, simpler user interface
than most podcast players. Podcast players don't always play programs in
date order or, worse, play them in _reverse_ date order, newest first. Audiobook
players don't seem to have this problem, so long as files are properly named.

So, every so often, I just run this script to update all the podcasts I listen
to, and then copy the entire set of directories to my Android phone using a file
manager. The file manager is smart enough not to copy files that are already
on the phone, so this is generally a quick operation.

## CAUTION

Downloading an offline copy of a podcast that has been running for years will
use a _lot_ of storage -- many gigabytes. I have a terabyte SD card in my
smartphone, and offline copies of podcasts take up a fair proportion of
that storage. `rsspodfetch.sh` can optionally reduce the audio quality of
streams as it downloads them, and this can save a lot of storage.

By default, `rsspodfetch.sh` downloads items whose publication date is
within the last year, but this can be changed on the command line if
necessary.

## Prerequisites

`rsspodfetch.sh` requires `wget`, `id3v2`, and `xsltproc`. The script checks that
these utilities are available on the `$PATH`, and will quit if they are not.

You'll also need `ffmpeg` if you enable quality reduction of the 
saved files.

## Usage

~~~
rsspodfetch.sh {feed_url} {output_dir} {album} {artist} {genre} {max_days_old}

feed_url     : the HTTP(S) URL from which to fetch the podcast RSS feed
output_dir   : the directory into which downloaded audio files will be saved
album        : the album tag to write into downloaded files
artist       : the artist tag to write into downloaded files
genre        : the genre tag to write into downloaded files
max_days_old : the oldest file to download (based on publication date) 
~~~

All arguments except `max_days_old` are mandatory. `max_days_old` defaults to 365.

Set the environment variable `REDUCE_QUALITY=yes` if you want to reduce the
audio quality after downloading. You'll probably need to edit the `ffmpeg` line
to set the bitrate, sample rate, etc., that you like.

## How it works 

The RSS file that defines an audio podcast has the format outlined below.
There is a header containing information about the podcast as a whole,
and then a series of <item> entries, one for each specific program.
Within the <item> you'll see the program title, the publication date,
and the stream URL.

~~~
<rss version="2.0"> 
<channel>
  <title>Title of the podcast</title>
  <item>
    <title>Title of this item</title>
    <description>Text description of this item</description>
    <enclosure url="audio_stream_url.mp3" type="audio/mpeg" />
    <pubDate>Publication date of the item in RFC2822 format</pubDate>
  </item>
  <item>
  ...
  </item>
  ...
</channel>
</rss>
~~~

`rsspodfetch.sh` retrieves and reads the RSS file, and ensures that there is a
local copy of the stream defined in each <item> entry. It saves the local copy
in a specified directory, using a name based on the program title and the
publication date.  Since a local audio file player will probably sort by
filename, if we want to play programs from oldest to newest, we must ensure
that the filename begins with the date, and that the date is in a format that
can be sorted by the player. In addition, we probably need to set the title tag
in the saved file so that it, too, begins with the date. This is because some
audio players will prefer the title tag to the filename, when it comes to
sorting. Because players like Smart Audiobook Player and Listen group files by
the 'album' tag, we must also ensure that each file in a specific podcast has
the same album tag.  Sometimes the podcast producer will set meaningful title
and album tags, but we can't rely on this -- we need to set tags for all files.

As each <item> in the RSS feed has a unique combination of title and
publication date, we can combine these to form the filename of the
local file, and also to ensure that we don't try to download streams
that are already in the output directory.

`rsspodfetch.sh` uses `xsltproc` to parse the XML of the RSS file. 
It does this by extracting each program's <item> entry, and writing
the relevant parts (title, date, and URL) to an intermediate text file, one
line at a time. On each line the variables are separated by tokens (default to 
"@@@"). The script then reads the text file line by line, downloading
each item from its URL.

Optionally the script will call `ffmpeg` to reduce the quality of the audio file.
Some podcast streams are delivered at absurdly high bitrates or sample rates for
human speech. Reducing the quality can radically reduce storage requirements,
while still storing a file that is listenable.

## Notes

At present, `rsspodfetch` supports only MP3 streams. This is because it uses
`id3v2` to apply tags to the files it downloads. MP3 format is almost
ubiquitous in the audio podcast world, but not completely.  To handle other
format's we'd need to update the utility to detect the file type, and then
invoke a tagger appropriate to that type, rather than `id3v2`. For MP4/M4A/M4B
files, for example, we could use AtomicParsley.

`rsspodfetch.sh` removes `?` and `:` characters from the names of files it
stores, replacing them with `_`. It also replaces double-quotes with single-quotes.
This is because some filesystems choke on
those characters. The tags stored in MP3 files -- also based on the <item>
title -- may still contain these characters: there's no problem using them in
tags. It's plausible that some 
filesystems will reject other characters that are sometimes found in the
titles of podcast programs, and which I haven't anticipated.

This fussiness about legal characters probably only comes to a head when
copying the downloaded files to a reader device. Most Linux filesystems
are pretty generous in the characters they accept, but players may
use FAT or exFAT filesystems, which are not. It's best to test with a 
small set of files (e.g., by specifying a small date range) before
downloading a ten-year podcast, only to find that half the files
can't be copied.

It would be possible to use the podcast title, as found in the RSS file, as the
'album' tag, and avoid the need to specific it on the command line. However, I
have conventions about how I tag my files, and I suspect that others who store
audio files for offline use probably do, too. So `rsspodfetch.sh` requires that
tag information be given on the command line. It sets the 'composer' tag to be
the same as the 'artist'. This would be easy to change, if necessary.

Please be aware that some podcast hosting servers are fussy, and might limit
the number of downloads in a particular time. Some block access via VPNs, for
some reason. I don't know why, but I've found the `wget` is more palatable to
podcast servers than `curl` is, which is why I've used `wget` in this utility.

`rsspodfetch.sh` only checks whether a file exists before it downloads; it
doesn't check anything else about the file. If a download fails, for any
reason, and leaves an incomplete file, it won't get overwritten on the next
update. Similarly, if the server delivers something that isn't an audio file
(because of some problem), that also won't get overwritten with an audio file
later.  It would be nice to check at least whether the stored file was the same
size as the file on the server, but podcast hosts don't always provide file
length information, so the utility would have to download the file completely
to find out. In the event of a failure, some manual clean-up of the local
directory might sometimes be necessary.

Not all podcasts have an RSS feed at all. Some podcast hosts do provide RSS,
but only to users who pay a fee. It should go without saying that `rsspodfetch.sh`
requires access to an RSS feed, that can be obtained by a `wget` operation, 
not just a web browser.

## Author and legal

`rsspodfetch.sh` is copyright (c)2026 Kevin Boone, released under the 
terms of the GNU Public Licence, v3.0. There is, of course, no warranty
of any kind.

## Revision history

Jan 10 2026  
Modified extension handling, to account for the fact that the URL might have
content after the file extension. At present, just assume .mp3 as the
extension, since we only handle MP3 streams.

Jan 9 2026  
First release.

