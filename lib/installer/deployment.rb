require 'installer/helpers'

module Installer
  class Deployment
    attr_reader :config
    attr_accessor :brokers, :nodes, :mqservers, :dbservers

    def self.role_map
      { :broker => 'Brokers',
        :node => 'Nodes',
        :mqserver => 'MQServers',
        :dbserver => 'DBServers',
      }
    end

    def initialize config, deployment
      @config = config
      self.class.role_map.each_pair do |role, hkey|
        set_role_list role, (deployment.has_key?(hkey) ? deployment[hkey].map{ |i| Installer::HostInstance.new(role, i) } : [])
      end
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

    def is_complete?
      [:brokers, :nodes, :mqservers, :dbservers].each do |group|
        list = self.send(group)
        if list.length == 0
          return false
        end
      end
      true
    end

    def is_valid?(check=:basic)
      [:brokers, :nodes, :mqservers, :dbservers].each do |group|
        list = self.send(group)
        role = group.to_s.chop.to_sym
        list.each do |host_instance|
          if host_instance.role != role
            return false if check == :basic
            raise Installer::HostInstanceRoleIncompatibleException.new("Found a host instance of type '#{host_instance.role.to_s}' in the #{group.to_s} list.")
          end
          host_instance.is_valid?(check)
        end
      end
    end
  end
end
