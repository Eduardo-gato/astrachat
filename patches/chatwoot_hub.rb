module Enterprise::ChatwootHub
  ENTERPRISE_BASE_URL = 'https://hub.2.chatwoot.com'.freeze

  def base_url
    return ENV.fetch('CHATWOOT_HUB_URL', ENTERPRISE_BASE_URL) if Rails.env.development?

    ENTERPRISE_BASE_URL
  end

  # AstraChat bake: força enterprise (bypassa o check que só limita 'premium')
  def pricing_plan
    'enterprise'
  end

  def pricing_plan_quantity
    9_999_999
  end
end
