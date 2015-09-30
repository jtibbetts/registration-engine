class LtiRegistrationWipsController < InheritedResources::Base
  def index
    action = params[:action]
    registration_id = params[:registration_id]
    registration = Lti2Tp::Registration.find(registration_id)
    @lti_registration_wip = LtiRegistrationWip.new

    # On orig registration, first assume tenant_name == name
    timeref = Time.now.strftime('%I%M.%S')
    # @lti_registration_wip.tenant_name = registration.message_type == 'registration' \
    #         ? "#{registration.tenant_basename}-#{timeref}" : registration.tenant_name

    #REI
    registration.tool_proxy_guid = registration.reg_key
    registration.save
    @lti_registration_wip.tenant_name = registration.reg_key

    @lti_registration_wip.registration_id = registration_id
    @lti_registration_wip.registration_return_url = params[:return_url]

    tcp_wrapper = JsonWrapper.new JSON.load(registration.tool_consumer_profile_json)
    @lti_registration_wip.support_email = tcp_wrapper.first_at('product_instance.support.email')
    @lti_registration_wip.product_name = tcp_wrapper.first_at('product_instance.product_info.product_name.default_value')

    @lti_registration_state = 'check_tenant'

    @lti_registration_wip.save

    # show UI here
    tp_base_url = Rails.application.config.tool_provider_registry.registry['tp_deployment_url']
    lti_tool_provider_base_url = Rails.application.config.tool_provider_registry.registry['lti_tool_provider_url']

    redirect_url = "#{lti_tool_provider_base_url}/tool_provider_review" \
                    + "?registration_id=#{registration.id}" \
                    + "&message_type=#{registration.message_type}" \
                    + "&tcp_uri=#{registration.tc_profile_url}" \
                    + "&return_url=#{tp_base_url}/lti_registration_wips/#{@lti_registration_wip.id}" \
                    + "&consumer_key=#{registration.reg_key}"
    logger.warn("RedirectUrl: #{redirect_url}")
    redirect_to redirect_url
  end

  def show
    @lti_registration_wip = LtiRegistrationWip.find(request.params[:id])
    @registration = Lti2Tp::Registration.find(@lti_registration_wip.registration_id)

    # get tool profile from REI_Impl
    lti_tool_provider_base_url = Rails.application.config.tool_provider_registry.registry['lti_tool_provider_url']
    response = HTTParty.get("#{lti_tool_provider_base_url}/tool_profiles?registration_id=#{@registration.id}")
    @registration.tool_profile_json = response.body
    #REI only

    @registration.save

    if @registration.message_type == "registration"
      show_registration
    else
      show_reregistration
    end
  end

  def show_registration
    tenant = Tenant.new
    tenant.tenant_name = @lti_registration_wip.tenant_name
    #REI only
    tenant.tenant_key = tenant.tenant_name

    begin
      tenant.save!
    rescue Exception => exc
      (@lti_registration_wip.errors[:tenant_name] << "Institution name is already in database") and return
    end

    disposition = @registration.prepare_tool_proxy('register')
    if @registration.is_status_failure? disposition
      redirect_to_registration(@registration, disposition) and return
    end

    tool_proxy_wrapper = JsonWrapper.new(@registration.tool_proxy_json)
    tool_proxy_response_wrapper = JsonWrapper.new(@registration.tool_proxy_response)

    tenant.tenant_key = tool_proxy_response_wrapper.first_at('tool_proxy_guid')
    @registration.tool_proxy_guid = tool_proxy_response_wrapper.first_at('tool_proxy_guid')

    @registration.final_secret = change_secret(tenant, tool_proxy_wrapper, tool_proxy_response_wrapper)
    tenant.secret = @registration.final_secret

    tenant.save

    change_credentials_in_REI

    @registration.tenant_id = tenant.id
    @registration.save

    redirect_to_registration @registration, disposition
  end

  def show_reregistration
    tenant = Tenant.where(:tenant_key=>@registration.reg_key).first
    disposition = @registration.prepare_tool_proxy('reregister')

    @registration.status = "reregistered"
    @registration.save!

    return_url = @registration.launch_presentation_return_url + disposition

    redirect_to_registration @registration, disposition
  end

  def complete_reregistration
    @registration = Lti2Tp::Registration.find(request.params[:registration_id])
    tenant_id = @registration.tenant_id
    tenant = Tenant.find(tenant_id)
    tool_proxy_wrapper = JsonWrapper.new(@registration.tool_proxy_json)
    tool_proxy_response_wrapper = JsonWrapper.new(@registration.tool_proxy_response)

    @registration.final_secret = change_secret(tenant, tool_proxy_wrapper, tool_proxy_response_wrapper)
    @registration.save!

    tenant.secret = @registration.final_secret
    tenant.save

    change_credentials_in_REI

    render :nothing => true, :status => '200'
  end

  def update
    @lti_registration_wip = LtiRegistrationWip.find(params[:id])
    @lti_registration_wip.tenant_name = params[:lti_registration_wip][:tenant_name]
    @lti_registration_wip.save

    registration = Lti2Tp::Registration.find(@lti_registration_wip.registration_id)
    registration.tenant_name = @lti_registration_wip.tenant_name
    registration.save

    show
  end

  private
  def change_credentials_in_REI
    # promote secret change to REU
    tp_base_url = Rails.application.config.tool_provider_registry.registry['tp_deployment_url']
    tool_proxy_uri = "#{tp_base_url}/tool_proxies/#{@registration.reg_key}"
    tool_proxy_encoded_uri = URI::escape(tool_proxy_uri)
    lti_tool_provider_base_url = Rails.application.config.tool_provider_registry.registry['lti_tool_provider_url']
    credentials_url = "#{lti_tool_provider_base_url}/change_credentials?" \
                            + "registration_id=#{@registration.id}" \
                            + "&final_secret=#{@registration.final_secret}" \
                            + "&tool_proxy_uri=#{tool_proxy_encoded_uri}"
    puts(credentials_url)
    response = HTTParty.get(credentials_url)
    puts("response code: #{response.code}")
  end

  def change_secret(tenant, tool_proxy_wrapper, tool_proxy_response_wrapper)
    if tool_proxy_wrapper.first_at('security_contract.shared_secret').present?
      final_secret = tool_proxy_wrapper.first_at('security_contract.shared_secret')
    else
      if tool_proxy_wrapper.first_at('security_contract.tp_half_shared_secret').present?
        final_secret = tool_proxy_response_wrapper.first_at('tc_half_shared_secret') \
          + tool_proxy_wrapper.first_at('security_contract.tp_half_shared_secret')
      end
    end
    final_secret
  end

  def redirect_to_registration registration, disposition
    redirect_to "#{@lti_registration_wip.registration_return_url}#{disposition}&id=#{registration.id}"
  end
end
