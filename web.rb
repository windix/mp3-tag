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
  
  @dir = File.join("/", escape_filename(f),  "*")
  @files = Dir.glob(@dir).sort
  
  send_header
  erb :index
end

get '/info/*' do |f|
  @path = File.join("/", f)

  #@info = ""
  buffer = StringIO.new
  old_stdout = $stdout
  $stdout = buffer

  if File.directory?(@path)
    dir = File.join(escape_filename(@path), "*.mp3")
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
  content_type 'text/html', :charset => 'utf-8'
end

def escape_filename(f)
  f.gsub(/([\[\]])/, '\\\\\1')
end

def func(file)
  mp3tag = Mp3Tag.new
  mp3tag.info(file, "GBK")

  #puts "#{file} #{File.ctime(file)}\n"
end


__END__

@@index

<h1><%= @dir %></h1>

<% @files.each do |f| %>
  <% if File.directory?(f) %>
    <a href="<%= "/info" + f %>">[+]</a> <a href="<%= "/browse" + f %>"><%= f %></a><br />
  <% else %>
    <a href="<%= "/info" + f %>">[+]</a> <%= f %><br />
  <% end %>    
<% end %>


@@info

<h1>Mp3 Info</h1>
<h2><%= @path %></h2>

<pre><%= @info %></pre>
