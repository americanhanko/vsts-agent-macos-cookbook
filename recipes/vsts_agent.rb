vsts_agent_macos 'agent_one' do
  action [:install, :configure, :install_service, :start_service]
end
