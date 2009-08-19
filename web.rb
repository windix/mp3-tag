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
  
  @dir = File.join(Mp3Tag::Utils.escape_filename(f),  "*")
  @files = Dir.glob(@dir).sort

  send_header
  erb :index
end

get '/info/*' do |f|
  @path = f

  #@info = ""
  buffer = StringIO.new
  old_stdout = $stdout
  $stdout = buffer

  if File.directory?(@path)
    dir = File.join(Mp3Tag::Utils.escape_filename(@path), "*.mp3")
    @files = Dir.glob(dir, File::FNM_CASEFOLD).sort

    #@files.each { |file| @info << func(file) }
    @files.each { |file| func(file) }
  else
    #@info << func(@path)
    func(@path)
  end

  @info = buffer.string
  $stdout = old_stdout

  send_header
  erb :info
end

def send_header
  #charset = RUBY_PLATFORM =~ /mswin32/ ? 'gb2312' : 'utf-8'
  content_type 'text/html', :charset => "utf-8"
end

def iconv(s)
  if Mp3Tag::Utils.is_win32?
    Mp3Tag::Utils.iconv(s, "GBK", "UTF-8")
  else
    s
  end
end

def func(file)
  mp3tag = Mp3Tag::Web.new("GBK")
  mp3tag.info(file)
end

__END__

@@index

<h1><%= @dir %></h1>

<% @files.each do |f| %>
  <% if File.directory?(f) %>
    <a href="<%= "/info/" + CGI.escape(f) %>">[+]</a> <a href="<%= "/browse/" + CGI.escape(f) %>"><%= iconv(f) %></a><br />
  <% else %>
    <a href="<%= "/info/" + CGI.escape(f) %>">[+]</a> <%= iconv(f) %><br />
  <% end %>    
<% end %>


@@info

<h1>Mp3 Info</h1>
<h2><%= iconv(@path) %></h2>

<pre><%= @info %></pre>
