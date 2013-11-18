require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == Example load-balancer model class
  #
  # Implements the LoadBalancerModel interface with dummy methods that just log
  # output representing actions that a normal implementation would perform,
  # without actually taking action against a load balancer.
  #
  class DummyLoadBalancerModel < LoadBalancerModel

    def get_pool_names
      @logger.debug "get pool names"
      []
    end

    def create_pool pool_name, monitor_name, params={} 
      params.merge!(@default_params)
      @logger.debug "create pool #{pool_name} with monitor #{monitor_name}"
      @logger.debug "dummy model create_pool params: #{params.inspect}"
      
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_pool pool_name, params={}
      params.merge!(@default_params)
      @logger.debug "delete pool #{pool_name}"
      @logger.debug "dummy model delete_pool params: #{params.inspect}"

      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_route_names
      @logger.debug "get route names"
      [] # Return an array of String representing routes.
    end

    def get_active_route_names
      @logger.debug "get active route names"
      [] # Return an array of String representing routes.
    end

    def create_route pool_name, route_name, path
      @logger.debug "create route #{route_name} from path #{path} to pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def attach_route route_name, virtual_server_name
      @logger.debug "attach route #{route_name} to virtual server #{virtual_server_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def detach_route route_name, virtual_server_name
      @logger.debug "detach route #{route_name} from virtual server #{virtual_server_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_route pool_name, route_name
      @logger.debug "delete route #{route_name} associated with pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_monitor_names
      @logger.debug "get monitor names"
      [] # Return an array of String representing monitors.
    end

    def create_monitor monitor_name, path, up_code, type, interval, timeout
      @logger.debug "create monitor #{monitor_name} using path #{path} with type #{type} and interval #{interval} and timeout #{timeout} where '#{up_code}' means up"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_monitor monitor_name
      @logger.debug "delete monitor #{monitor_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_pool_members pool_name
      @logger.debug "get members of pool #{pool_name}"
      [] # Return an array of String representing pool members.
    end

    def get_active_pool_members
      @logger.debug "get active members of pool #{pool_name}"
      [] # Return an array of String representing pool members.
    end

    def add_pool_member pool_name, address, port
      @logger.debug "add member #{address}:#{port} to pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def delete_pool_member pool_name, address, port
      @logger.debug "delete member #{address}:#{port} from pool #{pool_name}"
      [] # If using AsyncLoadBalancerController, return an array of jobids.
    end

    def get_job_status id
      @logger.debug "return status of job #{id}"
      "some JSON"
    end

    def authenticate host=@host, user=@user, passwd=@passwd
      @logger.debug "do some authentication stuff"

      @foo = "some temporary token or connection object"
    end

    def initialize host, user, passwd, logger
      @host, @user, @passwd, @logger = host, user, passwd, logger
      @default_params = { "host" => host, "user" => user, "passwd" => passwd }
      @logger.debug "do initialization stuff #{@host} : #{@user},#{@passwd}"
    end

  end

end
