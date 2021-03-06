require 'installer/helpers'

module Installer
  class Deployment
    include Installer::Helpers

    attr_reader :config
    attr_accessor :brokers, :nodes, :mqservers, :dbservers, :dns

    def self.role_map
      { :broker => 'Brokers',
        :node => 'Nodes',
        :mqserver => 'MQServers',
        :dbserver => 'DBServers',
      }
    end

    def self.list_map
      { :broker => :brokers,
        :node => :nodes,
        :mqserver => :mqservers,
        :dbserver => :dbservers,
      }
    end

    def self.roles
      @roles ||= self.role_map.keys.map{ |role| role.to_s }
    end

    def initialize config, deployment
      @config = config
      self.class.role_map.each_pair do |role, hkey|
        set_role_list role, (deployment.has_key?(hkey) ? deployment[hkey].map{ |i| Installer::HostInstance.new(role, i) } : [])
      end
      set_dns (deployment.has_key?('DNS') ? deployment['DNS'] : {})
    end

    def add_host_instance! host_instance
      list = get_role_list host_instance.role
      list << host_instance
      set_role_list host_instance.role, list
      save_to_disk!
    end

    def update_host_instance! host_instance, index
      list = get_role_list host_instance.role
      list[index] = host_instance
      set_role_list host_instance.role, list
      save_to_disk!
    end

    def remove_host_instance! host_instance, index
      list = get_role_list host_instance.role
      list.delete_at(index)
      set_role_list host_instance.role, list
      save_to_disk!
    end

    def to_hash
      { 'Brokers' => brokers.map{ |b| b.to_hash },
        'Nodes' => nodes.map{ |n| n.to_hash },
        'MQServers' => mqservers.map{ |m| m.to_hash },
        'DBServers' => dbservers.map{ |d| d.to_hash },
        'DNS' => dns,
      }
    end

    def save_to_disk!
      config.set_deployment self
      config.save_to_disk!
    end

    def get_role_list role
      listname = "#{role.to_s}s".to_sym
      self.send(listname)
    end

    def set_role_list role, list
      listname = "#{role.to_s}s".to_sym
      self.send("#{listname}=", list)
    end

    def set_dns dns
      @dns = dns
    end

    def find_host_instance_for_workflow host_instance_key=nil, specific_role=nil
      all_host_instances = []
      self.class.list_map.each_pair do |role,lsym|
        if not specific_role.nil? and role.to_s != specific_role
          next
        end
        list = self.send(lsym)
        group = self.class.role_map[role].chop
        for i in 0..(list.length - 1)
          current_key = "#{role.to_s}::#{i.to_s}"
          if not host_instance_key.nil? and host_instance_key == current_key
            return list[i]
          end
          all_host_instances << { :text => "#{group} - #{list[i].summarize}", :value => current_key }
        end
      end
      if not host_instance_key.nil?
        return nil
      end
      all_host_instances
    end

    def list_host_instances_for_workflow(role=nil)
      find_host_instance_for_workflow(nil, role)
    end

    # Expectations: this method will attempt to connect to the remote hosts via SSH
    # It notes if the remote system asks for a password.
    def check_remote_ssh
      failed_hosts = []
      by_ssh_host.each_pair do |ssh_host,instance_list|
        user = instance_list[0].user
        puts "\nChecking connection to #{ssh_host} with user #{user}...\n"
        success = system("ssh -oPasswordAuthentication=no -t -l #{user} #{ssh_host} 'sudo -n hostname'")
        if not success
          failed_hosts << "#{ssh_host} (user: #{user})"
        end
      end
      failed_hosts
    end

    def is_complete?
      [:brokers, :nodes, :mqservers, :dbservers].each do |group|
        list = self.send(group)
        if list.length == 0
          return false
        end
      end
      if not dns.has_key?('app_domain')
        return false
      end
      true
    end

    def is_valid?(check=:basic)
      # Check the host lists
      [:brokers, :nodes, :mqservers, :dbservers].each do |group|
        list = self.send(group)
        role = group.to_s.chop.to_sym
        seen_hosts = []
        list.each do |host_instance|
          if host_instance.role != role
            return false if check == :basic
            raise Installer::HostInstanceRoleIncompatibleException.new("Found a host instance of type '#{host_instance.role.to_s}' in the #{group.to_s} list.")
          end
          if seen_hosts.include?(host_instance.host)
            return false if check == :basic
            raise Installer::HostInstanceDuplicateTargetHostException.new("Multiple host instances in the #{group.to_s} list have the same target host or IP address")
          else
            seen_hosts << host_instance.host
          end
          host_instance.is_valid?(check)
        end
      end
      # Check the DNS setup
      if not dns.has_key?('app_domain') or not is_valid_domain?(dns['app_domain'])
        return false if check == :basic
      end
      true
    end

    # Return the host instance elements keyed by SSH host
    def by_ssh_host
      by_ssh_host = {}
      self.class.list_map.each_pair do |role,list|
        self.send(list).each do |host_instance|
          if not by_ssh_host.has_key?(host_instance.ssh_host)
            by_ssh_host[host_instance.ssh_host] = []
          end
          by_ssh_host[host_instance.ssh_host] << host_instance
        end
      end
      by_ssh_host
    end
  end
end
