require 'rubygems'
require 'rest_client'
require 'cgi'
require 'rexml/document'
require 'sinatra'
require 'erb'
require 'stringio'

require 'mp3tag'

get '/' do
  redirect '/browse/'
end

get '/browse/*' do |f|
  f = ENV['HOME'] if f.empty?
  @dir = f
  @files = Dir.glob(File.join(Mp3Tag::Utils.escape_filename(f), "*")).sort
  @up_level_dir = File.expand_path(File.join(f, ".."))

  send_header
  erb :index
end

get %r{/info/(.*)} do |f|
  @path = f
  @up_level_dir = File.expand_path(File.join(f, ".."))
  
  @info = get_result(:info, @path)
  send_header
  erb :info
end

get '/conv/*' do |f|
  @path = f
  @up_level_dir = File.expand_path(File.join(f, ".."))

  @info = get_result(:conv, @path)
  send_header
  erb :info
end

get '/cover_image/*' do |f|
  @path = f
  
  if File.file?(@path) && File.extname(@path).downcase == ".mp3"
    if (songs = Mp3Tag::Song.get_songs(@path)) && songs.length > 0
      if (image = songs.first.cover_image)
        content_type 'image/jpeg'
        return image
      end
    end
  end
end

def send_header
  content_type 'text/html', :charset => "utf-8"
end

def iconv(s)
  s = Mp3Tag::Utils.iconv(s, "GBK", "UTF-8") if Mp3Tag::Utils.is_win32?
  return s
end

def get_result(func, *params)
  mp3tag = Mp3Tag::Web.new("GBK")

  buffer = StringIO.new
  old_stdout = $stdout
  $stdout = buffer
  
  mp3tag.send(func, *params)
  
  info = buffer.string
  $stdout = old_stdout
  
  info
end

def get_url(action, path)
  "/#{action}/#{CGI.escape(path)}"
end

__END__

@@index

<h1><%= iconv(@dir) %></h1>

<a href="<%= get_url(:browse, @up_level_dir) %>">[..]</a><br />

<% @files.each do |f| %>
  <% if File.directory?(f) %>
    <a href="<%= get_url(:info, f) %>">[i]</a> <a href="<%= get_url(:browse, f) %>"><%= iconv(f) %></a><br />
  <% else %>
    <a href="<%= get_url(:info, f) %>">[i]</a> <%= iconv(f) %><br />
  <% end %>    
<% end %>

@@info

<h1>Mp3 Info</h1>
<h2><%= iconv(@path) %></h2>
<div>
<a href="<%= get_url(:browse, @up_level_dir) %>">[back]</a> | 
<a href="<%= get_url(:info, @path) %>">[info]</a> | 
<a href="<%= get_url(:conv, @path) %>">[conv]</a> |
<a href="<%= get_url(:cover_image, @path) %>">[cover]</a>
</div>

<pre><%= @info %></pre>
