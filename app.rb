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
#CMD = '/usr/bin/curl' unless defined?(CMD)
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
  property :last_body, Text
  
  validates_is_unique :url
  def down?
    current_status == 'down'
  end
end

class Configure
  include DataMapper::Resource
  property :id, Serial
  property :smtp_settings, Text
  property :notify_from, String
  property :retries, String, :default => 3
  property :sleep, String, :default => 1
  validates_is_number :retries,:sleep
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
  @config.notify_from = params[:notify_from]
  @config.sleep = params[:sleep]
  @config.retries = params[:retries]
  if @config.save
    redirect('/')
  else
    @smtp = @config.smtp_settings
    @smtp = YAML.load(@smtp) if !@smtp.nil?
    @smtp ||= {}
    @error = @config.errors.inspect
    haml :config
  end
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
    not_found_error
  end
end

get '/sites/:id/last_body' do
  @site = Site.get(params[:id])
  if @site
    @body = @site.last_body
    @body = @body.gsub(/\&/,'&amp;')
    @body = @body.gsub(/</,'&lt;')
    @body = @body.gsub(/</,'&gt;')
    haml :site_last_body
  else
    not_found_error
  end
end

get '/sites/:id/check' do
  @site = Site.get(params[:id])
  if @site
    check_site(@site)
    redirect '/'
  else
    not_found_error
  end
end

put '/sites' do
  @site = Site.get(params[:id])
  if @site
    set_site_params
    if @site.save
      redirect '/'
    else
      @error = @site.errors.inspect
      haml :site_form
    end
  else
    not_found_error
  end
end

delete '/sites' do
  @site = Site.get(params[:id])
  if @site
    @site.destroy
    redirect '/'
  else
    not_found_error
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
  def not_found_error
    render_error "id #{params[:id]} not found"
  end
  def render_error(error_text)
    @error = error_text
    haml :error
  end
end

def check_sites
  Site.all.each do |site|
    check_site(site)
  end
end

def check_site(site)
  site.last_check = Time.now
  status = result = nil
  (1..@config.retries.to_i).each do |x|
    result = get_url(site.url)
    status = is_down?(site,result) ? 'down' : 'up'
    break if status == 'up'
    sleep(@config.sleep.to_i)
  end
  if result.kind_of?(Net::HTTPResponse)
    site.last_body = result.body
    site.last_result = result.class
  else
    site.last_result = result.to_s
  end
  if site.current_status != status
    site.current_status = status
    site.status_changed = site.last_check
    notify_change(site)
  end
  raise "couldn't save" if !site.save
end

def get_url(uri)
  require 'net/http'
  uri = 'http://'+uri if uri !~ /^http:\/\//
  uri = uri + '/' if uri !~ /\/$/
  begin
    url = URI.parse(uri)
    req = Net::HTTP::Get.new(url.path)
    res = Net::HTTP.start(url.host, url.port) do |http|
      http.request(req)
    end
    res
  rescue Exception => e
    e
  end
#  result = `#{CMD} #{site.url}`
end

def is_down?(site,result)
  return false if result.kind_of?(Net::HTTPSuccess) || result.kind_of?(Net::HTTPRedirection)
  true
end

def notify_change(site)
  status = site.current_status
  body = <<-EOTXT
    zuptime reports that #{site.url} is now #{status}
    
    The response from the server was: #{site.last_result}
    
  EOTXT
  pony_params = {
    :from => @config.notify_from,
    :subject => "zuptime: #{site.url} is #{status}",
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
  if site.notify && site.notify != ''
    Pony.mail(pony_params)
  end
end