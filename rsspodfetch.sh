#!/bin/bash

## rsspodfetch.sh
##
## A script to keep local copies of podcast audio files in sync with the source;
##   that is, to convert podcast streams to local audiobooks.
## 
## Prerequisites: wget, xsltproc, id3v2, ffmpeg (if enabling quality reduction)
##
## Usage:
## rsspodfetch.sh {rss_feed_url} {output_dir} {album} {artist} {genre} {max_days_old}
##   feed_url     : the HTTP(S) URL from which to fetch the podcast RSS feed
##   output_dir   : the directory into which downloaded audio files will be saved
##   album        : the album tag to write into downloaded files
##   artist       : the artist tag to write into downloaded files
##   genre        : the genre tag to write into downloaded files
##   max_days_old : the oldest file to download (based on publication date) 
##
## All arguments except max_days_old are mandatory. max_days_old defaults to 365
##
## Note: at present, this utility only works with MP3 streams, and the stream URL must
##   have a name that ends in '.mp3'. This is because `id3v2` only works with
##   ID3 tags, as found in MP3.
## 
## Copyright (c)2026 Kevin Boone, GPLv3.0

## Set REDUCE_QUALITY to 'yes' if you want to reduce bitrate, etc, using ffmpeg.
## Of course, ffmpeg must be available. You'll need to tune the arguments to
##   ffmpeg, for the quality you require (deflt. 64kbits, 22kHz, mono). See
##   line ~200.

#REDUCE_QUALITY=yes

## Specify a delimiter for the fields in the intermediate TSV file. It can be
##   any string that is not going to appear anywhere in the podcast URL or title
DELIMITER=@@@

## Assign the command-line arguments to variables with more useful names
feed_url=$1
output_dir=$2
album=$3
artist=$4
genre=$5
max_days_old=$6

## Various temporary files that we will generate during the downloading
##   and parsing of the RSS file
rss_file=/tmp/$$.rss
xslt_file=/tmp/$$.xslt
tsv_file=/tmp/$$.tsv

## Let's check all the pre-requisites are in place before doing much else
if ! which xsltproc > /dev/null ; then
  echo Usage: $0 requires xsltproc, which seems not to be available
  exit
fi 
  
if ! which wget > /dev/null ; then
  echo Usage: $0 requires wget, which seems not to be available
  exit
fi 
  
if ! which id3v2 > /dev/null ; then
  echo Usage: $0 requires id3v2, which seems not to be available
  exit
fi 
  
## Let's make sure the command line specified the output directory, and
##   that it is writeable
if [ "$output_dir" == "" ] ; then
  echo Usage: $0 {feed_url} {output_directory}
  exit
fi

if [ ! -w "$output_dir" ]; then 
  echo $output_dir is not a writable directory
  exit
fi

if [ "$max_days_old" == "" ] ; then
  echo Maximum age not set: defaulting to 365 days 
  max_days_old=365
fi

## Get the RSS file, and abort if we can't
echo Fetching RSS file from $feed_url
wget -O $rss_file $feed_url 
if [[ $? -ne 0 ]] ; then
  echo Can\'t download RSS from $feed_url
  exit
fi

## This is the only bit of this utility that is remotely clever. We'll use
##  xsltproc to parse the RSS XML file into something that can be scanned and
##  parsed further by a simple shell script. We'll write the XSLT transformation
##  from this file into a file in /tmp, making this script self-contained. 
## The XSLT extracts the parts of the <item> definition that we really need --
##  the publication date, title, and stream URL. These will be written, one
##  item to a line, with the fields separated by $DELIMITER 
cat > $xslt_file << EOF
<xsl:stylesheet version="1.0"
   xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/rss/channel">
<xsl:for-each select="item">
  <xsl:value-of select="pubDate"/>$DELIMITER<xsl:value-of select="title"/>$DELIMITER<xsl:value-of select="enclosure/@url"/>$DELIMITER
</xsl:for-each>
</xsl:template>
</xsl:stylesheet>
EOF

## The output from the XSLT transformation is to the file $tsv_file
echo Parsing RSS file 
xsltproc $xslt_file $rss_file > $tsv_file

## Stop if the XLST transformation failed
if [[ $? -ne 0 ]] ; then
  echo Can\'t parse RSS file from $feed_url
  exit
fi

## Now we'll read the generated $tsv_file line-by-line, downloading from the 
##  stream URL when necessary
while read -r line; do
  # Only process not-blank lines
  if [ ! "$line" == "" ] ; then
    s=$line
    # Split the line into an array, with each token terminated by $DELIMITER
    # The syntax of this parameter substitution is pretty ugly, as you see
    array=();
    while [[ $s ]]; do
      array+=( "${s%%"$DELIMITER"*}" );
      s=${s#*"$DELIMITER"};
    done;

    # Having split the line into an array, extract the relevant bits into
    #   variables with more useful names 
    date=${array[0]}
    title=${array[1]}
    url=${array[2]}
    # Extract the file extension from the URL, but bear in mind we only
    #   support .mp3 at present
    extension="${url##*.}"
    # The URL may contain material after the extension, which we would have
    #   to remove, if were were handling anything but MP3 streams...
    extension="mp3" # ...but we're not, at present 

    # TODO: warn/fail if this isn't an MP3 stream

    # Make a sanitized title with no :, ?, *, or " characters, to use in the output
    #   filename; some filesystems choke on these characters. 
    # TODO: we might need to remove other characters as well, for maximum 
    #   compatibility
    sanitized_title="${title//:/_}"
    sanitized_title="${sanitized_title//\?/_}"
    sanitized_title="${sanitized_title//\*/@}"
    sanitized_title="${sanitized_title//\"/\'}"
    sanitized_title="${sanitized_title//\//\_}"

    # Convert the RFC2822 date-time from the RSS to a format that 
    #   will sort alphanumerically into date-time order
    # Note that I'm using the British date format YY-MM-DD, not the US
    #   YY-DD-MM, because the US version won't sort properly
    sortable_date=`date -d "$date" +%Y-%m-%d_%H_%M`

    # From the date and the RSS title, form a title tag and an output filename.
    # Both have the same form, but the filename uses the sanitized version
    #   of the filename, avoiding illegal characters. There should not no need
    #   to worry about specific characters in the title tag.
    sortable_title="${sortable_date} ${title}"
    sortable_sanitized_title="${sortable_date} ${sanitized_title}"
    output_file="${output_dir}/${sortable_sanitized_title}.${extension}"

    # Work out how old the stream is, from the publication date
    epoch_date_now=`date +%s`
    epoch_date_pub=`date -d "$date" +%s`
    days_old=$(( ($epoch_date_now - $epoch_date_pub) / 3600 / 24 ))

    # Print what we've worked out, for debugging purposes
    echo -e
    echo -e "date=$date"
    echo -e "sortable_date=$sortable_date"
    echo -e "title=$title"
    echo -e "sortable_title=$sortable_title"
    echo -e "sortable_sanitized_title=$sortable_sanitized_title"
    echo -e "url=$url"
    echo -e "extension=$extension"
    echo -e "output file=$output_file"

    echo -e "days old=${days_old}"

    # Now download the file if it is not already present in the output 
    #   directory, and if it is not too old
    if [ -e "$output_file" ] ; then
      echo File ${output_file} exists -- not downloading
    elif [[ $days_old -lt $max_days_old ]] ; then 
      echo Download ${url} to ${output_file}
      wget -O "${output_file}" "${url}"
      id3v2 -t "${sortable_title}" -A "${album}" -g "${genre}" -a "${artist}" \
              --TCOM "${artist}" "${output_file}" 

      # Adjust quality using ffmpeg, if specified. Note that ffmpeg respects
      #   existing tags, so we can do this after tagging with id3v2. Note also
      #   that we need -nostdin here, else ffmpeg fights with the script for 
      #   the console
      if [[ "$REDUCE_QUALITY" == "yes" ]] ; then
        echo Adjusting bitrate -- please be patient
        temp_audio_file="/tmp/$$.mp3"
        ffmpeg -nostdin -i "${output_file}" -ar 22050 \
              -ac 1 -c:a libmp3lame -q:a 4 "${temp_audio_file}" 
        mv "${temp_audio_file}" "${output_file}"
        rm "${temp_audio_file}"
      fi
    else
      echo Not downloading ${url} -- too old
    fi

  fi
done < $tsv_file

# If we get here, we probably did something successfully. Tidy
#  up temporary files
rm -f "$tsv_file" "$xslt_file" "$rss_file"


