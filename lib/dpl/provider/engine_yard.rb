module DPL
  class Provider
    class EngineYard < Provider
      experimental "Engine Yard"

      requires 'engineyard-cloud-client'

      def token
        options[:api_key] ||= if options[:email] and options[:password]
          EY::CloudClient.authenticate(options[:email], options[:password])
        else
          option(:api_key) # will raise
        end
      end

      def api
        @api ||= EY::CloudClient.new(:token => token)
      end

      def check_auth
        log "authenticated as %s" % api.current_user.email
      end

      def check_app
        remotes = `git remote -v`.scan(/\t[^\s]+\s/).map { |c| c.strip }.uniq
        @current_sha = `git rev-parse HEAD`.chomp
        resolver = api.resolve_app_environments(
          :app_name => options[:app],
          :account_name => options[:account],
          :environment_name => options[:environment],
          :remotes => remotes)
        resolver.one_match { @app_env = resolver.matches.first }
        resolver.no_matches { error resolver.errors.join("\n").inspect }
        resolver.many_matches do |matches|
          message = "Multiple matches possible, please be more specific:\n\n"
          matches.each do |appenv|
            message << "environment: '#{appenv.environment.name}' account: '#{appenv.environment.account.name}'\n"
          end
          error message
        end
        @app_env
      end

      def needs_key?
        false
      end

      def cleanup
        #DONT
      end

      def push_app
        print "deploying "
        deployment = EY::CloudClient::Deployment.deploy(api, @app_env, {:ref => @current_sha})
        result = poll_for_result(deployment)
        unless result.successful
          error "Deployment failed (see logs on Engine Yard)"
        end
      end

      def poll_for_result(deployment)
        until deployment.finished?
          sleep 5
          #TODO: configurable timeout?
          print "."
          deployment = EY::CloudClient::Deployment.get(api, deployment.app_environment, deployment.id)
        end
        puts "DONE"
        deployment
      end

      def deploy
        super
      rescue EY::CloudClient::Error => e
        error(e.message)
      end

    end
  end
end
