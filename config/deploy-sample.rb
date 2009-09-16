#========================
#CONFIG
#========================
set :application, "zuptime"
set :scm, :git
set :git_enable_submodules, 1
set :repository, "git://github.com/zippy/zuptime.git"
set :branch, "master"
set :ssh_options, { :forward_agent => true }
set :user, "your_user_name_here"
set :deploy_to, "/opt/apps/#{application}"
set :app_server, :passenger
set :domain, "your.domain.com"
#========================
#ROLES
#========================
role :app, domain
role :web, domain
role :db, domain, :primary => true
#========================
#CUSTOM
#========================
after 'deploy:symlink', :roles => :app do
  run "ln -nfs #{shared_path}/db #{release_path}/db" 
  run "ln -nfs #{shared_path}/config #{release_path}/config" 
end

after 'deploy:setup', :except => { :no_release => true } do
  run "mkdir #{shared_path}/db"
  run "mkdir #{shared_path}/config"
end

namespace :deploy do
  task :start, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end
  task :stop, :roles => :app do
  # Do nothing.
  end
  desc "Restart Application"
  task :restart, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end
  
end