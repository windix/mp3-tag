#!/usr/bin/ruby -w

require 'rubygems'
require 'id3lib'
require 'iconv'
require 'open-uri'

class String 
  def inspect_hex
    result = String.new
    result << "(#{self.size}) "
    self.each_byte do |b|
      result << "#{b.to_s(16).upcase} "
    end

    result
  end
end

class Mp3Tag
  VALID_ACTIONS = [ 'info', 'conv', 'cover', 'fname' ]

  RESERVED_IDS = [ :TIT2, :TPE1, :TALB, :TYER, :TRCK, :APIC ]
  ENC_INFO = { 0 => "ASCII", 1 => "UNICODE" }

  def initialize
    @from_gbk = Iconv.new('UTF-8', 'GBK')
    @gbk_to_ucs2 = Iconv.new('UCS-2', 'GBK')

    @from_big5 = Iconv.new('UTF-8', 'BIG5')
    @big5_to_ucs2 = Iconv.new('UCS-2', 'BIG5')

    @from_ucs2 = Iconv.new('UTF-8', 'UCS-2')
    @utf8_to_ucs2 = Iconv.new('UCS-2', 'UTF-8')

    @reserved_frames = {}
  end

  # Display mp3 file info
  def info(path, ascii_encoding)
    if prepare_songs(path)
      @songs.each do |song| 
        display_song_filename song
        process_tag song, "info", ascii_encoding
      end
    end
  end

  # Convert mp3 file's id3 tag info to unicode format
  def conv(path, ascii_encoding)
    if prepare_songs(path)
      @songs.each { |song| process_tag song, "conv", ascii_encoding }
      convert_tag ascii_encoding
    end
  end

  # Attach cover image
  def cover(path, cover_path)
    if load_cover(cover_path) && prepare_songs(path)
      @songs.each do |song| 
        display_song_filename song
        attach_cover song
      end
    end
  end

  def fname(path, pattern)
    if prepare_songs(path)
      @songs.each do |song|
        display_song_filename song
        update_tag_from_filename song, pattern
      end
    end

  end

  private
  
  # Prepare song files
  # when it's a single file, return it directly
  # when it's a directory, return all the song files inside it
  def prepare_songs(path)
    if path =~ /^~/
      path.sub!(/^~/, ENV['HOME'])
    end

    if File.file?(path) && File.extname(path).downcase == ".mp3"
      # file  
      @songs = path

    elsif File.directory?(path) 
      # dir
      @songs = Dir.glob(File.join(path, "*.mp3"), File::FNM_CASEFOLD)
      puts File.join(path, "*.mp3") if $DEBUG
      p @songs if $DEBUG

      @songs

    else
      puts "Invalid song file: #{path}"
      nil
    end
  end

  # Display song filename
  def display_song_filename song
    puts "Song: #{File.basename(song)}"
    puts
  end

  # Convert text to UTF-8 format for display purpose
  def convert_text_to_utf8(text, from_encoding)
    case from_encoding
      when "GBK" then @from_gbk.iconv(text)
      when "BIG5" then @from_big5.iconv(text)
      when "UNICODE" then @from_ucs2.iconv(text)
    end
  rescue
    nil
  end

  # Convert text to UNICODE (UCS-2) format to store in mp3 file
  def convert_text_to_ucs2(text, from_encoding)
    case from_encoding
      when "GBK" then @gbk_to_ucs2.iconv(text)
      when "BIG5" then @big5_to_ucs2.iconv(text)
      when "UTF-8" then @utf8_to_ucs2.iconv(text)
    end 
  rescue
    nil
  end

  # Go through all the ID3 tag frames one by one for the given song
  def process_tag(song, action = "info", ascii_encoding = "GBK")
    @reserved_frames[song] = {}
    
    tag = ID3Lib::Tag.new(song, ID3Lib::V_BOTH)

    tag.each do |frame|
      frame_info = ID3Lib::Info.frame(frame[:id])
      encoding = ENC_INFO[frame[:textenc]]
      
      @reserved_frames[song][frame[:id]] = frame if RESERVED_IDS.include? frame[:id]
      
      if action == "info"
        puts "#{frame_info[2]} (#{frame_info[1]})"
        puts "[#{encoding}] #{convert_text_to_utf8(frame[:text], 
          encoding == "UNICODE" ? encoding : ascii_encoding )}" 
      end
    end
    
    puts if action == "info"
    p @reserved_frames[song] if $DEBUG
  end

  # Convert mp3 file's id3 tag info to unicode format based on @reserved_frames
  def convert_tag(ascii_encoding = "GBK")
    @reserved_frames.each do |song, frames|
      display_song_filename song

      tag = ID3Lib::Tag.new(song, ID3Lib::V_BOTH)
      
      #remove all tags
      tag.strip!
      
      frames.each do |frame_id, frame|
        unless frame[:id] == :APIC
          encoding = ENC_INFO[frame[:textenc]]
          frame[:text] = convert_text_to_ucs2(frame[:text], ascii_encoding) if encoding == "ASCII"
          frame[:textenc] = 1
        end

        tag << frame
      end

      tag.update!(ID3Lib::V2)

      puts "Done!"
      puts
    end
  end

  # Load cover image file
  def load_cover(path)
    if URI.parse(path).scheme == "http"
      # remote file
      @cover = open(path).read

    elsif File.exist?(path)
      # local file
      
      @cover = File.read(path)
    else
      puts "Invalid cover image: #{path}"
      nil
    end
  
  rescue
    puts "Invalid cover image: #{path}"
    nil
  end
 
  # Update cover image for the song
  def attach_cover(song)
    tag = ID3Lib::Tag.new(song, ID3Lib::V_BOTH)
    
    # remove any existing covers
    tag.delete_if{ |frame| frame[:id] == :APIC }

    cover = {
      :id          => :APIC,
      :mimetype    => 'image/jpeg',
      :picturetype => 3,
      :description => 'Album cover',
      :textenc     => 0,
      :data        => @cover
    }

    tag << cover
    tag.update!(ID3Lib::V2)

    puts "Done!"
    puts
  end

  def update_tag_from_filename(song, pattern)
    filename = File.basename(song, ".mp3")
    
    tag = ID3Lib::Tag.new(song, ID3Lib::V_BOTH)

    if filename =~ /(^\d+)[.|\s]?\s*(.*$)/
      #remove all tags
      tag.strip!
      
      tag << { :id => :TRCK, :text => convert_text_to_ucs2($1.chomp, "UTF-8"), :textenc => 1 }
      tag << { :id => :TIT2, :text => convert_text_to_ucs2($2.chomp, "UTF-8"), :textenc => 1 }

      tag.update!(ID3Lib::V2)
      
      puts "Done!"
    else
      puts "Failed to parse..."
    end
    puts

  end

  # Validate action from command line argument
  def self.valid_action?(action)
    if VALID_ACTIONS.include? action.downcase
      action.downcase.to_sym
    else
      nil
    end
  end
end


if __FILE__ == $0

  if ARGV.length == 0 || !(action = Mp3Tag.valid_action?(ARGV.shift))
    puts "Usage: mp3tag <info / conv / cover> [-big5] <file.mp3 / dir> [<cover_image>]"
  else
    mp3Tag = Mp3Tag.new

    #begin
      if ARGV[0] == "-big5"
        ascii_encoding = "BIG5" 
        ARGV.shift
      else
        ascii_encoding = "GBK"
      end

      puts ascii_encoding if $DEBUG
      puts action if $DEBUG

      case action
        when :info  then mp3Tag.info(ARGV[0], ascii_encoding)
        when :conv  then mp3Tag.conv(ARGV[0], ascii_encoding)
        when :cover then mp3Tag.cover(ARGV[0], ARGV[1])
        when :fname then mp3Tag.fname(ARGV[0], '')
      end
    
    #rescue => e
    #  puts "Invalid argument! " + e.message
    #end

  end
end

__END__

TODO:

  1. refactor current version
  2. rename based on file name
  3. convert to simplified Chinese
  4. automatically download cover arts

