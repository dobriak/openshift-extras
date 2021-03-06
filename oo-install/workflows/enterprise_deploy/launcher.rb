#!/usr/bin/env ruby

require 'yaml'
require 'net/ssh'

CONFIG_FILE = ENV['HOME'] + '/.openshift/oo-install-cfg.yml'

# If this is the add-a-node scenario, the node to be installed will
# be passed via the command line
@target_node_index = ARGV[0].nil? ? nil : ARGV[0].split('::')[1].to_i
@target_node_host = nil

# Default and baked-in config values for the openshift.sh deployment
@env_map = { 'CONF_INSTALL_COMPONENTS' => 'all' }

# These values will be passed on the command line
@env_input_map = {
  'subscription_type' => ['CONF_INSTALL_METHOD'],
  'repos_base' => ['CONF_REPOS_BASE'],
  'rhel_repo' => ['CONF_RHEL_REPO'],
  'jboss_repo_base' => ['CONF_JBOSS_REPO_BASE'],
  'rhel_optional_repo' => ['CONF_RHEL_OPTIONAL_REPO'],
  'rh_username' => ['CONF_SM_REG_NAME','CONF_RHN_REG_NAME'],
  'rh_password' => ['CONF_SM_REG_PASS','CONF_RHN_REG_PASS'],
  'sm_reg_pool' => ['CONF_SM_REG_POOL'],
  'sm_reg_pool_rhel' => ['CONF_SM_REG_POOL_RHEL'],
  'rhn_reg_actkey' => ['CONF_RHN_REG_ACTKEY'],
}

# Pull values that may have been passed on the command line into the launcher
@env_input_map.each_pair do |input,target_list|
  env_key = "OO_INSTALL_#{input.upcase}"
  if ENV.has_key?(env_key)
    target_list.each do |target|
      @env_map[target] = ENV[env_key]
    end
  end
end

@utility_install_order = ['named','datastore','activemq','broker','node']

# Maps openshift.sh roles to oo-install deployment components
@role_map =
{ 'named' => { 'deploy_list' => 'Brokers', 'role' => 'broker', 'env_var' => 'CONF_NAMED_HOSTNAME' },
  'broker' => { 'deploy_list' => 'Brokers', 'role' => 'broker', 'env_var' => 'CONF_BROKER_HOSTNAME' },
  'node' => { 'deploy_list' => 'Nodes', 'role' => 'node', 'env_var' => 'CONF_NODE_HOSTNAME' },
  'activemq' => { 'deploy_list' => 'MQServers', 'role' => 'mqserver', 'env_var' => 'CONF_ACTIVEMQ_HOSTNAME' },
  'datastore' => { 'deploy_list' => 'DBServers', 'role' => 'dbserver', 'env_var' => 'CONF_DATASTORE_HOSTNAME' },
}

# Will map hosts to roles
@hosts = {}

def env_setup
  @env_map.each_pair.map{ |k,v| "#{k}=#{v}" }.join(' ')
end

config = YAML.load_file(CONFIG_FILE)

# Set values from deployment configuration
if config.has_key?('Deployment')
  @deployment_cfg = config['Deployment']

  # First, make a host map and a complete env map
  @role_map.keys.each do |role|
    # We only support multiple nodes; bail if we have multiple host instances for other roles.
    if not role == 'node' and @deployment_cfg[@role_map[role]['deploy_list']].length > 1
      puts "This workflow can only handle deployments containing a single #{role}. Exiting."
      exit 1
    end

    for idx in 0..(@deployment_cfg[@role_map[role]['deploy_list']].length - 1)
      host_instance = @deployment_cfg[@role_map[role]['deploy_list']][idx]
      if role == 'node' and @target_node_index == idx
        @target_node_host = host_instance['ssh_host']
      end
      # The host map helps us sanity check and call openshift.sh jobs
      if not @hosts.has_key?(host_instance['ssh_host'])
        @hosts[host_instance['ssh_host']] = { 'roles' => [], 'username' => host_instance['user'], 'host' => host_instance['host'] }
      end
      @hosts[host_instance['ssh_host']]['roles'] << role

      # The env map is passed to each job, but nodes are handled individually
      if not role == 'node'
        @env_map[@role_map[role]['env_var']] = host_instance['host']
      end
    end
  end

  @env_map['CONF_DOMAIN'] = @deployment_cfg['DNS']['app_domain']
end

if @hosts.empty?
  puts "The config file at #{CONFIG_FILE} does not contain OpenShift deployment information. Exiting."
  exit 1
end

if not @target_node_index.nil? and @target_node_host.nil?
  puts "The list of nodes in the config file at #{CONFIG_FILE} is shorter than the index of the specified node host to be installed. Exiting."
  exit 1
end

# Make sure the per-host config is legit
@hosts.each_pair do |ssh_host,info|
  roles = info['roles']
  duplicate = roles.detect{ |e| roles.count(e) > 1 }
  if not duplicate.nil?
    puts "Multiple instances of role type '#{@role_map[duplicate]['role']}' are specified for installation on the same target host (#{ssh_host}).\nThis is not a valid configuration. Exiting."
    exit 1
  end
  if not @target_node_host.nil? and @target_node_host == ssh_host and (roles.length > 1 or not roles[0] == 'node')
    puts "The specified node to be added also contains other OpenShift components.\nNodes can only be added as standalone components on their own systems. Exiting."
    exit 1
  end
end

# Set the installation order
host_order = []
@utility_install_order.each do |role|
  if not role == 'node' and not @target_node_host.nil?
    next
  end
  @hosts.select{ |key,hash| hash['roles'].include?(role) }.each do |matched_host|
    ssh_host = matched_host[0]
    if not @target_node_host.nil? and not @target_node_host == ssh_host
      next
    end
    if not host_order.include?(ssh_host)
      host_order << ssh_host
    end
  end
end

# Summarize the plan
if @target_node_host.nil?
  puts "Preparing to install OpenShift Enterprise on the following hosts:\n"
else
  puts "Preparing to add this node to an OpenShift Enterprise system:\n"
end
host_order.each do |ssh_host|
  puts "  * #{ssh_host}: #{@hosts[ssh_host]['roles'].join(', ')}\n"
end

# Run the jobs
host_order.each do |ssh_host|
  user = @hosts[ssh_host]['username']
  @env_map['CONF_INSTALL_COMPONENTS'] = @hosts[ssh_host]['roles'].join(',')

  # Only include the node config setting for hosts that will have a node installation
  if @hosts[ssh_host]['roles'].include?('node')
    @env_map[@role_map['node']['env_var']] = @hosts[ssh_host]['host']
  else
    @env_map.delete(@role_map['node']['env_var'])
  end

  puts "Copying deployment script to target #{ssh_host}.\n"
  system "scp #{File.dirname(__FILE__)}/openshift.sh #{user}@#{ssh_host}:~/"
  puts "Running deployment\n"
  system "ssh #{user}@#{ssh_host} 'chmod u+x ~/openshift.sh \&\& #{env_setup} ~/openshift.sh \&\& reboot'"

  puts "Installation on target #{ssh_host} completed.\n"
end

exit
