include_recipe 'homebrew::default'
homebrew_package 'git'
homebrew_package 'openssl'

directory '/usr/local/lib/' do
  recursive true
  owner Agent.admin_user
  group Agent.staff_group
end

link '/usr/local/lib/libcrypto.1.0.0.dylib' do
  to '/usr/local/opt/openssl/lib/libcrypto.1.0.0.dylib'
  owner Agent.admin_user
  group Agent.staff_group
end

link '/usr/local/lib/libssl.1.0.0.dylib' do
  to '/usr/local/opt/openssl/lib/libssl.1.0.0.dylib'
  owner Agent.admin_user
  group Agent.staff_group
end

directory Agent.agent_home do
  owner Agent.admin_user
  group Agent.staff_group
end

directory "#{Agent.admin_library}/LaunchAgents" do
  recursive true
  owner Agent.admin_user
  group Agent.staff_group
end

directory "#{Agent.admin_home}/Downloads/vsts-agent" do
  recursive true
  owner Agent.admin_user
  group Agent.staff_group
end

remote_file Agent.target_path do
  source Agent.release_download_url
  owner Agent.admin_user
  group Agent.staff_group
  show_progress true
end

tar_extract Agent.target_path do
  target_dir Agent.agent_home
  group Agent.staff_group
  user Agent.admin_user
  action :extract_local
  only_if { Agent.needs_update? }
end

directory "#{Agent.admin_home}/Downloads/vsts-agent" do
  user Agent.admin_user
  group Agent.staff_group
  action :nothing
  recursive true
  subscribes :delete, 'tar_extract[vsts agent source]', :delayed
end

execute 'bootstrap the agent' do
  cwd Agent.agent_home
  user Agent.admin_user
  command ['./bin/Agent.Listener', 'configure', '--unattended', '--acceptTeeEula']
  environment Agent.vsts_environment
  not_if { Agent.credentials? }
  live_stream true
  ignore_failure true
end

execute 'verify agent unconfigured' do
  cwd Agent.agent_home
  user Agent.admin_user
  returns 2
  command ['./bin/Agent.Listener']
  live_stream true
  not_if { Agent.credentials? }
  notifies :run, 'execute[replace the agent]', :immediately
end

execute 'replace the agent' do
  cwd Agent.agent_home
  user Agent.admin_user
  command ['./bin/Agent.Listener', 'configure', '--replace', '--unattended', '--acceptTeeEula']
  environment Agent.vsts_environment
  live_stream true
  action :nothing
end

directory 'create log directory' do
  path Agent.service_log_path
  recursive true
  owner Agent.admin_user
  group Agent.staff_group
end

ruby_block 'recursive permissions for logs' do
  block { ::FileUtils.chown_R Agent.admin_user, Agent.staff_group, Agent.service_log_path }
  action :nothing
  subscribes :run, 'directory[create log directory]', :immediately
end

file 'service program' do
  path "#{Agent.agent_home}/runsvc.sh"
  owner Agent.admin_user
  group Agent.staff_group
  mode 0o775
  content lazy { ::IO.read "#{Agent.agent_home}/bin/runsvc.sh" }
  action :create
end

file 'create agent service file' do
  path "#{Agent.agent_home}/.service"
  owner Agent.admin_user
  group Agent.staff_group
  content Agent.launchd_plist
  action :create
end

template 'create environment file' do
  path "#{Agent.agent_home}/.env"
  source 'env.erb'
  owner Agent.admin_user
  group Agent.staff_group
  mode 0o755
  cookbook 'vsts_agent_macos'
end

launchd 'create launchd service plist' do
  path Agent.launchd_plist
  type 'agent'
  owner Agent.admin_user
  label Agent.service_name
  program_arguments ["#{Agent.agent_home}/bin/runsvc.sh"]
  username Agent.admin_user
  working_directory Agent.agent_home
  run_at_load true
  standard_out_path ::File.join(Agent.service_log_path, 'stdout.log')
  standard_error_path ::File.join(Agent.service_log_path, 'stderr.log')
  environment_variables VSTS_AGENT_SVC: '1'
  session_type 'user'
  action [:create, :enable]
end

macosx_service 'restart-agent-service' do
  service_name Agent.service_name
  user Agent.admin_user
  action [:enable, :start]
end

macosx_service 'restart-agent-service' do
  service_name Agent.service_name
  user Agent.admin_user
  action :nothing
  subscribes :restart, 'template[environment file]'
  subscribes :run, 'execute[replace the agent]'
end
