require 'rubygems'
require 'rest_client'
require 'cgi'
require 'rexml/document'
require 'sinatra'
require 'erb'

require 'mp3tag'

get '/dir/*' do |f|
  f = ENV['HOME'] if f.empty?
  
  @dir = File.join(escape_filename(f),  "*")
  @files = Dir.glob(@dir).sort
  
  send_header
  erb :index
end

get '/info/*' do |f|
  mp3tag = Mp3Tag.new 
  
  @dir = escape_filename(f)
  
  mp3tag.info(@dir, "GBK")

  send_header
  erb :info
end


def send_header
  content_type 'text/html', :charset => 'utf-8'
end

def escape_filename(f)
  #File.join("/", f.gsub(/([()\[\]])/, '\\\\\1'))
  File.join("/", f.gsub(/([()\[\]])/, '\\\\\1'))
end

__END__

@@index

<h1><%= @dir %></h1>

<% @files.each do |f| %>
  <% if File.directory?(f) %>
    <a href="<%= "/info" + f %>">[+]</a> <a href="<%= "/dir" + f %>"><%= f %></a><br />
  <% else %>
    <a href="<%= "/info" + f %>">[+]</a> <%= f %><br />
  <% end %>    
<% end %>


@@info

<h1>Mp3 Info</h1>
<h2><%= @dir %></h2>

