require 'rubygems'
require 'sinatra'

set :public,   File.expand_path(File.dirname(__FILE__) + '/public') #Include your public folder
set :views,    File.expand_path(File.dirname(__FILE__) + '/views')  #Include the views

root_dir = File.dirname(__FILE__)
set :environment, ENV['RACK_ENV'].to_sym
set :root,        root_dir
set :app_file,    File.join(root_dir, 'app.rb')
disable :run

run Sinatra.application