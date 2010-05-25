require 'net/smtp'

set :application, "obs-webui"

# git settings
set :scm, :git
set :repository,  "git://gitorious.org/opensuse/build-service.git"
set :branch, "master"
set :deploy_via, :remote_cache
set :git_enable_submodules, 1
set :git_subdir, '/src/webui'
set :migrate_target, :current

set :deploy_notification_to, ['tschmidt@suse.de', 'coolo@suse.de', 'adrian@suse.de']
server "buildserviceapi.suse.de", :app, :web, :db, :primary => true

# If you aren't deploying to /u/apps/#{application} on the target
# servers (which is the default), you can specify the actual location
# via the :deploy_to variable:
set :deploy_to, "/srv/www/vhosts/opensuse.org/#{application}"
set :runit_name, "webclient"
set :static, "build.o.o"

# set variables for different target deployments
task :stage do
  set :deploy_to, "/srv/www/vhosts/opensuse.org/stage/#{application}"
  set :runit_name, "webclient_stage"
  set :branch, "master"
  set :static, "build.o.o-stage/stage"
end

ssh_options[:forward_agent] = true
default_run_options[:pty] = true
set :normalize_asset_timestamps, false

# tasks are run with this user
set :user, "root"
# spinner is run with this user
set :runner, "root"

after "deploy:update_code", "config:symlink_shared_config"
after "deploy:update_code", "config:sync_static"
after "deploy:symlink", "config:permissions"

# workaround because we are using a subdirectory of the git repo as rails root
before "deploy:finalize_update", "deploy:use_subdir"
after "deploy:finalize_update", "deploy:reset_subdir"
after "deploy:finalize_update", "deploy:notify"

after :deploy, 'deploy:cleanup' # only keep 5 releases
before "deploy:update_code", "deploy:test_suite"

namespace :config do

  desc "Install saved configs from /shared/ dir"
  task :symlink_shared_config do
    run "rm #{release_path}#{git_subdir}/config/options.yml"
    run "ln -s #{shared_path}/options.yml #{release_path}#{git_subdir}/config/"
    run "rm -f #{release_path}#{git_subdir}/config/environments/production.rb"
    run "ln -s #{shared_path}/production.rb #{release_path}#{git_subdir}/config/environments/"
    run "ln -s #{shared_path}/database.db #{release_path}#{git_subdir}/db/"
    run "ln -s #{shared_path}/repositories.rb #{release_path}#{git_subdir}/config/"
    run "rm -r #{release_path}#{git_subdir}/app/views/maintenance"
    run "ln -s #{shared_path}/maintenance #{release_path}#{git_subdir}/app/views"
    run "rm #{release_path}#{git_subdir}/config/database.yml"
    run "ln -s #{shared_path}/database.yml #{release_path}#{git_subdir}/config/database.yml"
  end

  desc "Set permissions"
  task :permissions do
    run "chown -R lighttpd #{current_path}/db #{current_path}/tmp #{current_path}/public/main"
  end

  desc "Sync public to static.o.o"
  task :sync_static do
    `rsync  --delete-after --exclude=themes -av public/ -e 'ssh -p2212' proxy-opensuse.suse.de:/srv/www/vhosts/static.opensuse.org/hosts/#{static}`
  end

end

# server restarting
namespace :deploy do
  task :start do
    run "sv start /service/#{runit_name}-*"
    run "sv start /service/delayed_job_#{runit_name}"
  end

  task :restart do
    run "for i in /service/#{runit_name}-*; do sv restart $i; sleep 5; done"
    run "sv 1 /service/delayed_job_#{runit_name}"
  end

  task :stop do
    run "sv stop /service/#{runit_name}-*"
    run "sv stop /service/delayed_job_#{runit_name}"
  end

  task :use_subdir do
    set :latest_release_bak, latest_release
    set :latest_release, "#{latest_release}#{git_subdir}"
    run "cp #{latest_release_bak}/REVISION #{latest_release}"
  end

  task :reset_subdir do
    set :latest_release, latest_release_bak
  end

  task :symlink, :except => { :no_release => true } do
    on_rollback do
      if previous_release
        run "rm -f #{current_path}; ln -s #{previous_release}#{git_subdir} #{current_path}; true"
      else
        logger.important "no previous release to rollback to, rollback of symlink skipped"
      end
    end

    run "rm -f #{current_path} && ln -s #{latest_release}#{git_subdir} #{current_path}"
  end

  desc "Send email notification of deployment"
  task :notify do
    #diff = `#{source.local.diff(current_revision)}`
    diff_log = `#{source.local.log( source.next_revision(current_revision) )}`
    user = `whoami`
    body = %Q[From: obs-webui-deploy@suse.de
To: #{deploy_notification_to.join(", ")}
Subject: obs-#{runit_name} deployed by #{user}

Git log:
#{diff_log}]

    Net::SMTP.start('relay.suse.de', 25) do |smtp|
      smtp.send_message body, 'obs-webui-deploy@suse.de', deploy_notification_to
    end
  end
  
  task :test_suite do
    Dir.glob('**/*.rb').each do |f|
      if !system("ruby -c -d #{f} > /dev/null")
         puts "syntax error in #{f} - will not deploy"
         exit 1
      end
    end
    if !system("rake --trace check_syntax")
      puts "Error in syntax check - will not deploy"
      exit 1
    end
    if !system("rake test")
      puts "Error on rake test - will not deploy"
      exit 1
    end
  end

end


