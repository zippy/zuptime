# myapp.rb
require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'dm-aggregates'
require 'haml'
require 'pony'
if File.exists?('config/config.rb')
  require 'config/config.rb'
end

DataMapper.setup(:default, "sqlite3:///#{Dir.pwd}/db/zuptime.db")

class Site
  include DataMapper::Resource

  property :id, Serial
  property :url, String
  property :notify, Text
  property :last_check, DateTime
  property :status_changed, DateTime
  property :current_status, String
  property :last_result, Text
  
  validates_is_unique :url
end

Site.auto_upgrade!
#Site.auto_migrate!

get '/' do
  @sites = Site.all
  haml :index
end

get '/sites/new' do
  @site = Site.new
  haml :site_form
end

get '/sites/check' do
  check_sites
  redirect '/'
end

get '/sites/:id' do
  @site = Site.get(params[:id])
  if @site
    haml :site_form
  else
    'not found'
  end
end

put '/sites' do
  @site = Site.get(params[:id])
  if @site
    set_site_params
    if @site.save
      redirect '/'
    else
      @site.errors.inspect
    end
  else
    'not found'
  end
end

delete '/sites' do
  @site = Site.get(params[:id])
  if @site
    @site.destroy
    redirect '/'
  else
    'not found'
  end
end

post '/sites' do
  @site = Site.new
  set_site_params
  @site.save
  redirect '/'
end

helpers do
  def set_site_params
    @site.url = params[:url]
    @site.notify = params[:notify]
  end
  def delete_link(model_object,url,text)
    %Q|<a href="#{url}" onclick="if (confirm('Are you sure?')) { var f = document.createElement('form'); f.style.display = 'none'; this.parentNode.appendChild(f); f.method = 'POST'; f.action = this.href;var m = document.createElement('input'); m.setAttribute('type', 'hidden'); m.setAttribute('name', '_method'); m.setAttribute('value', 'DELETE'); f.appendChild(m);var m = document.createElement('input'); m.setAttribute('type', 'hidden'); m.setAttribute('name', 'id'); m.setAttribute('value', '#{model_object.id}'); f.appendChild(m);f.submit(); };return false;">#{text}</a>|
  end
  def standard_date_time(time)
    time.asctime
  end
end

def check_sites
  Site.all.each do |site|
    site.last_result = `/usr/bin/curl #{site.url}`
    site.last_check = Time.now
    if 
      status = $? == 0 ? 'up' : 'down'
    else
      status = 'down'
    end
    if site.current_status != status
      site.current_status = status
      site.status_changed = site.last_check
      body = "Site Status Changed: #{status} (#{site.url})\n"
      body += "\nstatus from curl was #{$?}" if status == 'down'
      pony_params = {
        :from => 'zuptime@harris-braun.com',
        :subject => "Site Status Changed: #{status} (#{site.url})",
        :body => body
        
      }
      if defined?(SMTP_SETTING)
        pony_params[:via] = :smtp
        pony_params[:smtp] = SMTP_SETTING
      end
      pony_params[:to] = site.notify
      Pony.mail(pony_params)
    end
    site.save
  end
end