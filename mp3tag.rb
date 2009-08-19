#!/usr/bin/ruby -w

require 'rubygems'
require 'id3lib'
require 'iconv'
require 'open-uri'
require 'rchardet'

module Mp3Tag
  RESERVED_IDS = [ :TIT2, :TPE1, :TALB, :TYER, :TRCK, :APIC ]
  ENC_INFO = { 0 => "ASCII", 1 => "UNICODE" }

  def self.set_encoding(output_encoding)
    # under Chinese Win32 platform, file and dir names returns in GBK    
    if Utils.is_win32?
      @@input_encoding = "GBK"
    else
      @@input_encoding = "UTF-8"
    end
    
    # depends on environment: 
    # for CLI, output_encoding is the same as input_encoding based on platform
    # for Web, output_encoding is always UTF-8
    # this has been set during initialize for each sub-class
    
    @@output_encoding = output_encoding
  end
  
  def self.input_encoding
    @@input_encoding
  end
  
  def self.output_encoding
    @@output_encoding
  end

  class Utils
    # Conv between encodings
    def self.iconv(string, from = Mp3Tag::input_encoding, to = Mp3Tag::output_encoding)
      return string if from == to
      Iconv.iconv("#{to}//IGNORE", from, string).join
    rescue => ex
      ex.success.join
    end
  
    # Load cover image file
    def self.load_file_content(path)
      if ["http", "https"].include? URI.parse(path).scheme
        # remote file
        open(path).read
      elsif File.exist?(path)
        # local file
        File.read(path)
      end
    rescue
    end
    
    # escape for Dir.glob to make it work
    def self.escape_filename(f)
      f.gsub(/([\[\]])/, '\\\\\1')
    end
    
    # detect platform
    def self.is_win32?
      RUBY_PLATFORM =~ /mswin32/
    end
    
  end # of class Utils

  class Tag
    attr_reader :id, :encoding

    def initialize(id, text, encoding)
      @id, @text, @encoding = id, text, encoding
      @tag_name = nil
    end

    def reserved?
      RESERVED_IDS.include? @id     
    end

    def to_s(default_encoding_for_ASCII = "GBK")
      "#{tag_name}\n#{text(default_encoding_for_ASCII)}\n"
    end

    def text(default_encoding_for_ASCII = "GBK")
      if (@text)
        from_encoding = case @encoding 
                        when "ASCII" then  default_encoding_for_ASCII
                        when "UNICODE" then "UCS-2"
                        end

        text = Utils.iconv(@text, from_encoding)
      else
        ""
      end
    end

    def tag_name
      unless @tag_name
        frame_info = ID3Lib::Info.frame(@id)
        star = "* " if reserved?
        @tag_name = "#{star}#{frame_info[2]} (#{@id})"
      end

      @tag_name
    end

    def is_cover?
      true if (@id == :APIC)
    end

    def get_frame(ascii_encoding)
      { 
        :id => @id, 
        :text => text(ascii_encoding, "UCS-2"), 
        :textenc => 1                           # fixed to UNICODE
      }
    end
  end # of class Tag

  class CoverTag < Tag
    def initialize(id, data)
      @id, @data, @text, @encoding = id, data, nil, "ASCII"
      @tag_name = nil
    end

    def get_frame(ascii_encoding)
      {
        :id          => @id,
        :mimetype    => 'image/jpeg',
        :picturetype => 3,
        :description => 'Album cover',
        :textenc     => 0,                    # fixed to ASCII
        :data        => @data
      }
    end
  end # of class CoverTag

  class Song
    attr_accessor :path, :tags

    # Get song files from the given path
    def self.get_songs(path)
      songs = []

      if path
        path = File.expand_path(path)

        if File.directory?(path)
          # dir
          Dir.glob(File.join(Utils.escape_filename(path), "*.mp3"), File::FNM_CASEFOLD).each do |path|
            songs << Song.new(path)
          end
        elsif File.file?(path) && File.extname(path).downcase == ".mp3"
          # file
          songs << Song.new(path)
        end
      end

      songs
    end

    def initialize(path) 
      @path = path
      @cover_image = nil      
      
      load_tags
    end

    def require_convert?
      @tags.each do |tag|
        return true if !tag.is_cover? && tag.reserved? && tag.encoding == "ASCII"
      end
      false
    end

    def song_name
      Utils.iconv(File.basename(@path))
    end

    def to_s(default_encoding_for_ASCII = "GBK")
      output = "Song name: '#{song_name}'\n"
      output << "Need convert: #{ require_convert? ? "YES" : "NO" }\n";
      output << "\n"

      max_length = @tags.inject(0) { |max, x| max > x.tag_name.length ? max : x.tag_name.length }

      @tags.each do |tag|
        output << tag.tag_name.rjust(max_length) << " : " << "[#{tag.encoding}] " <<
        tag.text(default_encoding_for_ASCII) << "\n"
      end

      output << "\n"
    end

    def attach_cover!(cover_path)
      unless @cover_image
        # load cover image
        if ['.jpg', '.jpeg', '.png', '.gif'].include?(File.extname(cover_path).downcase)
          @cover_image = Utils.load_file_content(cover_path)
        end
      end
      
      if @cover_image
        # remove all covers (if any)
        tags.delete_if { |tag| tag.is_cover? }
        
        # attach cover image to song
        tags << CoverTag.new(:APIC, @cover_image)
        
        true
      end
    end

    def update_tag!(ascii_encoding = "GBK")
      frames = ID3Lib::Tag.new(@path, ID3Lib::V_BOTH)

      # remove all frames
      frames.strip!

      @tags.each do |tag|
        frames << tag.get_frame(ascii_encoding) if tag.reserved?
      end

      frames.update!(ID3Lib::V2)
      
      load_tags
    end

    private
    def load_tags
      @tags = []
      
      frames = ID3Lib::Tag.new(@path, ID3Lib::V_BOTH)

      frames.each do |frame|
        if frame[:id] == :APIC
          @tags << CoverTag.new(frame[:id], frame[:data])
        else
          @tags << Tag.new(frame[:id], frame[:text], ENC_INFO[frame[:textenc]])
        end
      end
    end
    
    def update_tag_from_filename(song, pattern)
      # TODO
      
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
    
  end # of class Song

  class Base
    def initialize(default_ascii_encoding = "GBK")
      @ascii_encoding = default_ascii_encoding
    end
    
    # Display mp3 file info
    def info(paths)
      paths.each do |path|
        get_songs(path).each do |song|
          puts song.to_s(@ascii_encoding)
        end
      end
    end
    
    # Convert mp3 file's id3 tag info to unicode format
    def conv(paths)
      paths.each do |path|
        get_songs(path).each do |song|
          print "Convert '#{song.song_name}'... "

          if (song.require_convert?)
            song.update_tag!(@ascii_encoding)
            puts "Done!"
          else
            puts "No need. "
          end
        end
      end
    end
    
    # Attach cover image
    def cover(paths, cover_path)
      paths.each do |path|
        get_songs(path).each do |song|
          print "Attach cover image to '#{song.song_name}'... "

          if song.attach_cover!(cover_path)
            song.update_tag!(@ascii_encoding)
            puts "Done!"
          else
            puts "Failed to load cover image: '#{cover_path}'"
            exit
          end
        end
      end
    end
    
    # Update tag based on filename
    def fname
    end
    
    private

    def get_songs(path)
      songs = Song.get_songs(path)
      puts "Found #{songs.size} #{songs.size == 1 ? 'song' : 'songs'} from path '#{Utils.iconv(path)}'"
      puts

      songs
    end
  end

  class CLI < Base
    VALID_ACTIONS = [ 'info', 'conv', 'cover' ]

    def initialize()
      Mp3Tag::set_encoding(Utils.is_win32? ? "GBK" : "UTF-8")
      
      if ARGV.length == 0 || !(action = valid_action?(ARGV.shift))
        puts cli_usage
      else
        if ARGV[0] == "-big5"
          ascii_encoding = "BIG5" 
          ARGV.shift
        else
          ascii_encoding = "GBK"
        end
        
        super(ascii_encoding)

        send(action)
      end
    end

    ## ACTIONS

    def info
      super(ARGV)
    end

    def conv
      super(ARGV)
    end

    # Attach cover image
    def cover
      cover_path = ARGV.pop
      paths = ARGV
      
      super(paths, cover_path)
    end

    private
    
    def cli_usage
      return <<-USAGE
Convert Chinese Mp3 ID3tag to ID3tag V2 / Unicode

Usage: mp3tag <#{VALID_ACTIONS.join(' / ')}> [-big5] <file.mp3 / dir> [<cover_image>]

Examples:
  mp3tag info test.mp3
  mp3tag conv -big5 ~/music/
  mp3tag cover test.mp3 http://test.com/123.jpg
  mp3tag fname test.mp3

      USAGE
    end

    # Validate action from command line argument
    def valid_action?(action)
      if VALID_ACTIONS.include? action.downcase
        action.downcase.to_sym
      else
        nil
      end
    end
    
  end # of class CLI

  class Web < Base
    def initialize(default_ascii_encoding = "GBK")
      Mp3Tag::set_encoding("UTF-8")
      super(default_ascii_encoding)
    end
  end
  
end

Mp3Tag::CLI.new if __FILE__ == $0

__END__

TODO:

2. rename based on file name
3. convert to simplified Chinese
4. automatically download cover arts
5. backup
