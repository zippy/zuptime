# myapp.rb
require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'dm-aggregates'
require 'haml'
require 'pony'
require 'yaml'
if File.exists?('config/config.rb')
  require 'config/config.rb'
end
CMD = '/usr/bin/curl' unless defined?(CMD)
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

class Configure
  include DataMapper::Resource
  property :id, Serial
  property :smtp_settings, Text
end

Site.auto_upgrade!
Configure.auto_upgrade!
#Site.auto_migrate!

before do
  if request.path_info !~ /\/config/
    @config = Configure.get(1)
    if !@config
      redirect '/config/edit' if !@config
      halt
    end
  end
end

get '/config/edit' do
  @config = Configure.get(1)
  @config ||= Configure.new
  @smtp = @config.smtp_settings
  @smtp = YAML.load(@smtp) if !@smtp.nil?
  @smtp ||= {}
  haml :config
end

post '/config/set' do
  @config = Configure.get(1)
  @config ||= Configure.new
  @config.smtp_settings = params[:smtp].to_yaml
  @config.save ? redirect('/') : @config.errors.inspect
end

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

get '/sites/:id/check' do
  @site = Site.get(params[:id])
  if @site
    check_site(@site)
    redirect '/'
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
  def options_for_select(options,value)
    options.collect do |o|
      case o
      when Hash
        txt = o.keys[0]
        val = o[txt]
        %Q|<option #{value==val ? 'selected' : ''} value="#{val}">#{txt}</option>|
      else
        %Q|<option #{value==o ? 'selected' : ''} value="#{o}">#{o}</option>|
      end
    end.join ''
  end
end

def check_sites
  Site.all.each do |site|
    check_site(site)
  end
end

def check_site(site)
  site.last_result = `#{CMD} #{site.url}`
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
    body += "\nstatus was #{$?}" if status == 'down'
    pony_params = {
      :from => 'zuptime@harris-braun.com',
      :subject => "Site Status Changed: #{status} (#{site.url})",
      :body => body
      
    }
    @smtp = @config.smtp_settings
    @smtp = YAML.load(@smtp) if !@smtp.nil?
    @smtp.keys.each {|k| @smtp[k.to_sym] = @smtp[k]}
    @smtp['auth'] = @smtp['auth'].to_sym if @smtp['auth']
    if @smtp
      pony_params[:via] = :smtp
      pony_params[:smtp] = @smtp
    end
    pony_params[:to] = site.notify
    Pony.mail(pony_params)
  end
  site.save
end