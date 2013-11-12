require 'rubygems'
require 'parseconfig'
require 'openshift/load-balancer/controllers/load_balancer'
require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == F5 Load Balancer Controller
  #
  # Represents the F5 load balancer for the OpenShift Enterprise
  # installation.  On initalization, the object queries the configured
  # F5 BIG-IP node for the configured pools and builds a table of Pool
  # objects.
  #
  class F5LoadBalancerController < LoadBalancerController

    # == F5 Pool object
    #
    # Represents the F5 pool.  On initialization, the object queries F5
    # BIG-IP using the F5LoadBalancerController object provided as bigip
    # to obtain the members of the pool named by pool_name.  These pool
    # members are stored in @members using one string of the form
    # address:port to represent each pool member.
    #
    class Pool < LoadBalancerController::Pool
      def initialize lb_controller, lb_model, pool_name
        @lb_controller, @lb_model, @name = lb_controller, lb_model, pool_name
        @members = @lb_model.get_pool_members pool_name
      end

      # Add a member to the object's internal list of members.  This
      # method does not update F5; use the update method to send the
      # updated list of pool members to F5 BIG-IP.
      def add_member address, port
        member = address + ':' + port.to_s
        raise LBControllerException.new "Adding gear #{member} to pool #{@name}, of which the gear is already a member" if @members.include? member
        @members.push member
        pending = [self.name, [address, port.to_s]]
        @lb_controller.pending_add_member_ops.push pending unless @lb_controller.pending_delete_member_ops.delete pending
      end

      # Remove a member from the object's internal list of members.
      # This method does not update F5; use the update method to force
      # an update.
      def delete_member address, port
        member = address + ':' + port.to_s
        raise LBControllerException.new "Deleting gear #{member} from pool #{@name}, of which the gear is not a member" unless @members.include? member
        @members.delete member
        pending = [self.name, [address, port.to_s]]
        @lb_controller.pending_delete_member_ops.push pending unless @lb_controller.pending_add_member_ops.delete pending
      end
    end

    attr_reader :pending_add_member_ops, :pending_delete_member_ops

    def read_config
      cfg = ParseConfig.new('/etc/openshift/load-balancer.conf')

      @bigip_host = cfg['BIGIP_HOST'] || '127.0.0.1'
      @bigip_username = cfg['BIGIP_USERNAME'] || 'admin'
      @bigip_password = cfg['BIGIP_PASSWORD'] || 'passwd'

      @virtual_server_name = cfg['VIRTUAL_SERVER']
    end

    def override_config meta
      @logger.info "F5 override_config called."
      if meta.has_key?('VIRTUAL_SERVER')
        @virtual_server_name = meta['VIRTUAL_SERVER']
      end
    end

    def create_pool pool_name, monitor_name=nil, meta
      raise LBControllerException.new "Pool already exists: #{pool_name}" if @pools.include? pool_name
      
      @logger.debug "f5 controller create_pool meta: #{meta.inspect}"

      @lb_model.create_pools [pool_name], [monitor_name]

      @pools[pool_name] = Pool.new self, @lb_model, pool_name
    end

    def delete_pool pool_name
      raise LBControllerException.new "Pool not found: #{pool_name}" unless @pools.include? pool_name

      update # in case we have pending delete operations for the pool.

      @lb_model.delete_pools [pool_name]

      @pools.delete pool_name
    end

    def create_route pool_name, profile_name, profile_path
      raise LBControllerException.new "Profile already exists: #{profile_name}" if @routes.include? profile_name

      @lb_model.create_route pool_name, profile_name, profile_path
      @lb_model.attach_route profile_name, @virtual_server_name if @virtual_server_name

      @routes.push profile_name
      @active_routes.push profile_name
    end

    def delete_route pool_name, route_name
      raise LBControllerException.new "Profile not found: #{route_name}" unless @routes.include? route_name

      @lb_model.detach_route route_name, @virtual_server_name if @virtual_server_name
      @lb_model.delete_route pool_name, route_name if @active_routes.include? route_name

      @routes.delete route_name
      @active_routes.delete route_name
    end

    def create_monitor monitor_name, path, up_code, type, interval, timeout
      raise LBControllerException.new "Monitor already exists: #{monitor_name}" if @monitors.include? monitor_name

      @lb_model.create_monitor monitor_name, path, up_code, type, interval, timeout

      @monitors.push monitor_name
    end

    def delete_monitor monitor_name, pool_name=nil
      raise LBControllerException.new "Monitor not found: #{monitor_name}" unless @monitors.include? monitor_name

      @lb_model.delete_monitor monitor_name if @monitors.include? monitor_name

      @monitors.delete monitor_name
    end

    def update
      adds = @pending_add_member_ops.inject(Hash.new {Array.new}) {|h,(k,v)| h[k] = h[k].push v; h}
      dels = @pending_delete_member_ops.inject(Hash.new {Array.new}) {|h,(k,v)| h[k] = h[k].push v; h}
      @lb_model.add_pool_members adds.keys, adds.values unless adds.empty?
      @lb_model.delete_pool_members dels.keys, dels.values unless dels.empty?
      @pending_add_member_ops = []
      @pending_delete_member_ops = []
    end

    def initialize lb_model_class, logger
      read_config

      @logger = logger

      @logger.info "Connecting to F5 BIG-IP at host #{@bigip_host}..."
      @lb_model = lb_model_class.new @bigip_host, @bigip_username, @bigip_password, @logger
      @lb_model.authenticate @bigip_host, @bigip_username, @bigip_password

      @pools = Hash[@lb_model.get_pool_names.map {|pool_name| [pool_name, Pool.new(self, @lb_model, pool_name)]}]
      @routes = @lb_model.get_route_names
      @active_routes = @lb_model.get_active_route_names
      @monitors = @lb_model.get_monitor_names

      @pending_add_member_ops = []
      @pending_delete_member_ops = []
    end
  end

end
