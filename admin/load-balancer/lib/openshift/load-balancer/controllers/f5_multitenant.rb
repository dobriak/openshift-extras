require 'rubygems'
require 'parseconfig'
require 'openshift/load-balancer/controllers/load_balancer'
require 'openshift/load-balancer/models/load_balancer'

require 'openshift/load-balancer/controllers/f5'

module OpenShift

  class F5LoadBalancerMultitenantController < LoadBalancerController
  
    #Initializes an array of lb_controller objects with values overriden by the contents of meta
    def initialize_controllers meta

      #split meta into hash of hashes
      multi = Hash.new { |h,k| h[k] = Hash.new(&h.default_proc) }
      #select keys named varname<number>, eg hostname7
      meta.select{ |key,value| key.match(/\d+/)}.each do |key,value|
        varname,varnum = key.split(/(\d+)$/)
        #multi['7']['hostname'] = value
        multi[varnum][varname] = value
      end
      StandardError.new "Configuration variables not found, or using the wrong naming convention." if multi.empty?

      #init only if there is no controller with the given controller key
      @controller_keys = [] #array of the currently processed keys
      multi.each do |multi_key,multi_value|
        #check if all required parameters are specified
        missing_params = (@required_params - multi_value.keys)
        StandardError.new "Missing required parameters: #{multi_key} - #{missing_params.join(',')}" unless mising_params.empty?
        
        controller_key = generate_controller_key(multi_value['host'], multi_value['tenant'], multi_value['service_port'])
        @controller_keys << controller_key

        unless @lb_controllers.has_key?(controller_key)
          lb_controller = @lb_controller_class.new @lb_model_class, @logger, multi_value
          @logger.info "Found #{lb_controller.pools.length} pools:\n" +
                       lb_controller.pools.map{|k,v|"  #{k} (#{v.members.length} members)"}.join("\n")
          @lb_controllers[controller_key] = lb_controller
        end
      end

      #@logger.info "initialize_controllers: processed #{@controller_keys.count} controller objects"
    end

    def generate_controller_key host, tenant, service_port
      "#{host}:#{tenant}:#{service_port}"
    end


    def create_pool pool_name, monitor_name=nil, meta
      initialize_controllers meta
      @controller_keys.each do |key|
        @lb_controllers[key].create_pool pool_name, monitor_name
        #Update pools?
      end
    end

    def delete_pool pool_name, meta
      initialize_controllers meta
      @controller_keys.each do |key|
        @lb_controllers[key].delete_pool pool_name
        #Update pools?
      end      
    end

    def create_route pool_name, profile_name, profile_path, meta
      initialize_controllers meta   
      @controller_keys.each do |key|
        @lb_controllers[key].create_route pool_name, profile_name, profile_path
        #Update routes?
      end
    end

    def delete_route pool_name, route_name, meta
      initialize_controllers meta
      @controller_keys.each do |key|
        @lb_controllers[key].delete_route pool_name, route_name
      end
      update
    end

    def create_monitor monitor_name, path, up_code, type, interval, timeout, meta
      initialize_controllers meta
      @controller_keys.each do |key|
        @lb_controllers[key].create_monitor monitor_name, path, up_code, type, interval, timeout
        #Update monitors?
      end
    end

    def delete_monitor monitor_name, pool_name=nil, meta
      initialize_controllers meta
      @controller_keys.each do |key|
        @lb_controllers[key].delete_monitor monitor_name, pool_name
        #Update monitors?
      end      
    end

    def update     
      @controller_keys.each do |key|
        @lb_controllers[key].update
      end
    end
    
    def pools
      #return a hash of all pools, override pools with the same pool name
      all_pools = {}
      @controller_keys.each do |key|
        @lb_controllers[key].pools.each {|k,v| all_pools[k] = v}
      end
      all_pools
    end
    
    def routes
      all_routes = []
      @controller_keys.each do |key|
        all_routes.concat @lb_controllers[key].routes
      end
      all_routes  
    end
    
    def active_routes
      all_active_routes = []
      @controller_keys.each do |key|
        all_active_routes.concat @lb_controllers[key].active_routes
      end
      all_active_routes     
    end
    
    def monitors
      all_monitors = []
      @controller_keys.each do |key|
        all_monitors.concat @lb_controllers[key].monitors
      end
      all_monitors
    end

    def reset_controller_keys
      @controller_keys = @default_keys
    end


    def initialize lb_model_class, logger, meta = {}
      @logger = logger
      @lb_model_class = lb_model_class
      @lb_controller_class = OpenShift::F5LoadBalancerController

      @pools = {}
      @routes = []
      @active_routes = []
      @monitors = []
      
      @required_params = %w[host tenant service_port]
           
      @lb_controllers = {}
      @controller_keys = []
      @default_keys = []
      
      @pending_add_member_ops = []
      @pending_delete_member_ops = []
    end
  end

end
