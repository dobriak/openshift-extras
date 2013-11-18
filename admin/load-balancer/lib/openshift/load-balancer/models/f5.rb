require 'openshift/load-balancer/models/load_balancer'

module OpenShift

  # == Load-balancer model class for the F5 BIG-IP LTM load balancer.
  #
  # Presents direct access to an F5 BIG-IP LTM load balancer using the
  # iControl SOAP interface.
  #
  class F5LoadBalancerModel < LoadBalancerModel

    def get_pool_names
      @bigip['LocalLB.Pool'].get_list.map {|pool| pool[8..-1]}
    end

    def create_pools pool_names, monitor_names, params={}
      params.merge!(@default_params)

      @bigip['LocalLB.Pool'].create pool_names.map {|pool| "/Common/#{pool}"}, ['LB_METHOD_ROUND_ROBIN'], []
      @bigip['LocalLB.Pool'].set_monitor_association pool_names.zip(monitor_names).map { |pool,monitor|
        if monitor
          {
            :pool_name => "/Common/#{pool}",
            :monitor_rule => {
              :type => 'MONITOR_RULE_TYPE_SINGLE',
              :quorum => 1,
              :monitor_templates => [monitor],
            },
          }
        else
          {
            :pool_name => "/Common/#{pool}",
            :monitor_rule => {
              :type => 'MONITOR_RULE_TYPE_NONE',
              :quorum => 1,
              :monitor_templates => [],
            },
          }
        end
      }
    end

    def delete_pools pool_names, params={}
      params.merge!(@default_params)
      @bigip['LocalLB.Pool'].delete_pool pool_names.map {|pool| "/Common/#{pool}"}
    end

    def get_route_names
      @bigip['LocalLB.ProfileHttpClass'].get_list.map {|pool| pool[8..-1]}
    end

    def get_active_route_names
      @bigip['LocalLB.VirtualServer'].get_httpclass_profile(['ose-vlan'])[0].map{|profile| profile.profile_name[8..-1]}
    end

    def create_routes pool_names, routes
      route_names, paths = routes.transpose
      @bigip['LocalLB.ProfileHttpClass'].create route_names.map {|name| "/Common/#{name}"}
      @bigip['LocalLB.ProfileHttpClass'].add_path_match_pattern route_names.map {|name| "/Common/#{name}"}, paths.map {|path| [{:pattern=>"#{path}(|/.*)$", :is_glob=>false}]}
      @bigip['LocalLB.ProfileHttpClass'].set_pool_name route_names.map {|name| "/Common/#{name}"}, pool_names.map{|name| {:value=>"/Common/#{name}", :default_flag=>false}}
      @bigip['LocalLB.ProfileHttpClass'].set_rewrite_url route_names.map {|name| "/Common/#{name}"}, paths.map{|path| {:value=>"[string map { \"#{path}\" \"/\" } [HTTP::uri]]", :default_flag=>false}}
    end

    def attach_routes route_names, virtual_server_names
      priority = @bigip['LocalLB.VirtualServer'].get_httpclass_profile(['ose-vlan'])[0].map{|pri| pri.priority}.max || 0
      @bigip['LocalLB.VirtualServer'].add_httpclass_profile virtual_server_names, [route_names.map {|name| {:profile_name=>"/Common/#{name}", :priority=>(priority += 1)}}]
    end

    def detach_routes route_names, virtual_server_names
      @bigip['LocalLB.VirtualServer'].remove_httpclass_profile virtual_server_names, [route_names.map {|n| {:profile_name=>"/Common/#{n}", :priority=>0}}]
    end

    def delete_routes pool_names, route_names
      @bigip['LocalLB.ProfileHttpClass'].delete_profile route_names.map {|name| "/Common/#{name}"}
    end

    def get_monitor_names
      @bigip['LocalLB.Monitor'].get_template_list.map {|template| template.template_name}
    end

    def create_monitor monitor_name, path, up_code, type, interval, timeout
      type = type == 'https-ecv' ? 'https' : 'http'
      @bigip['LocalLB.Monitor'].create_template [{:template_name=>monitor_name, :template_type=>'TTYPE_HTTP'}], [{:parent_template=>type, :interval=>Integer(interval), :timeout=>timeout, :dest_ipport=>{:address_type=>'ATYPE_STAR_ADDRESS_STAR_PORT', :ipport=>{:address=>'0.0.0.0', :port=>0}}, :is_read_only=>false, :is_directly_usable=>true}]
      @bigip['LocalLB.Monitor'].set_template_string_property [monitor_name, monitor_name], [{:type=>'STYPE_SEND', :value=>"GET #{path}\\r\\n"}, {:type=>'STYPE_RECEIVE', :value=>up_code}]
    end

    def delete_monitor monitor_name
      @bigip['LocalLB.Monitor'].delete_template [monitor_name]
    end

    def get_pool_members pool_name
      @bigip['LocalLB.Pool'].get_member(["/Common/#{pool_name}"])[0].collect do |pool_member|
          pool_member['address'] + ':' + pool_member['port'].to_s
        end
    end

    alias_method :get_active_pool_members, :get_pool_members

    def add_pool_members pool_names, member_lists
      @bigip['LocalLB.Pool'].add_member pool_names.map {|pool| "/Common/#{pool}"}, member_lists.map {|members| members.map {|address,port| { 'address' => address, 'port' => port }}}
    end

    def delete_pool_members pool_names, member_lists
      @bigip['LocalLB.Pool'].remove_member pool_names.map {|pool| "/Common/#{pool}"}, member_lists.map {|members| members.map {|address,port| { 'address' => address, 'port' => port }}}
    end

    def authenticate host=@host, user=@user, passwd=@passwd
      @bigip = F5::IControl.new(host, user, passwd,
                                ['System.Session', 'LocalLB.Pool', 'LocalLB.VirtualServer', 'LocalLB.ProfileHttpClass', 'LocalLB.Monitor']).get_interfaces
    end

    def initialize host, user, passwd, logger
      @host, @user, @passwd, @logger = host, user, passwd, loggera
      @default_params = { "host" => host, "user" => user, "passwd" => passwd }
    end

  end

end
