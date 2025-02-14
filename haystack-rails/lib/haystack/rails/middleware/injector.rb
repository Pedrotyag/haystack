
module Haystack
  module Rails
    module Middleware
      class Injector
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, response = @app.call(env)

          if html_response?(headers)
            body_content = extract_body(response)
            response_body = inject_script(body_content, env)
            headers['Content-Length'] = response_body.bytesize.to_s
            response = [response_body]
          end

          [status, headers, response]
        end

        private

        def html_response?(headers)
          headers['Content-Type']&.include?('text/html')
        end

        def extract_body(response)
          # Se response responde a :body, usamos isso; caso contrário, se for um array, juntamos os elementos.
          if response.respond_to?(:body)
            response.body.to_s
          elsif response.respond_to?(:join)
            response.join
          else
            response.to_s
          end
        end

        def inject_script(body, env)
          config = Haystack.instance_variable_get(:@global_configuration)

          dsn = config.js.dsn || ENV['HAYSTACK_DSN']

          script_content = generate_script(
            config: config,
            dsn: dsn,
            user_data: fetch_user_data(env, config),
            session_data: fetch_session_data(env),
            flash_messages: fetch_flash_messages(env),
            request_params: fetch_request_params(env)
          )

          body.sub('</head>', "#{script_content}\n</head>")
        end

        def fetch_request_params(env)
          controller = env['action_controller.instance']
          return {} unless controller

          # Converte para hash seguro e filtra dados sensíveis
          controller.params.to_unsafe_h
            .except(:password, :password_confirmation, :credit_card)
            .deep_transform_keys { |k| k.to_s.underscore }
        rescue => e
          { error: "params_error: #{e.message}" }
        end

        # Obtém a instância do usuário atual do controller
        def fetch_current_user(env)
          controller = env['action_controller.instance']
          return unless controller

          instance_variables = controller.instance_variables.each_with_object({}) do |var, hash|
            hash[var.to_s] = controller.instance_variable_get(var)
          end

          instance_variables['@current_user']
        end

        # Constrói os dados do usuário com base nas configurações dinâmicas
        def fetch_user_data(env, config)
          current_user = fetch_current_user(env)
          return {} unless current_user

          ip_address = env['action_controller.instance']&.request&.remote_ip

          {
            id: current_user.id,
            username: fetch_user_attribute(current_user, config.js.user_name_method, :name),
            email: fetch_user_attribute(current_user, config.js.user_email_method, :email),
            url: fetch_user_url(current_user, config.js.user_url_method),
            image_url: fetch_user_attribute(current_user, config.js.user_image_method, :avatar_image_url),
            ip_address: ip_address
          }
        end

        # Obtém um atributo do usuário de forma segura
        def fetch_user_attribute(user, method, default)
          return unless user
          method ||= default
          user.public_send(method) if user.respond_to?(method)
        end

        # Obtém a URL do usuário de forma segura
        def fetch_user_url(user, method)
          return unless user && method
          ::Rails.application.routes.url_helpers.public_send(method, user)
        end

        # Captura os dados da sessão
        def fetch_session_data(env)
          session = env['rack.session'] || {}

          warden_user = session['warden.user.user.key']

          processed_warden = if warden_user && warden_user.is_a?(Array) && warden_user[0].is_a?(Array)
                                {
                                  user_id: warden_user.dig(0, 0)&.to_s,
                                  password_hash: warden_user.dig(1)&.to_s
                                }
                              else
                                warden_user.to_s
                              end

          # Captura chaves padrão da sessão
          session_info = {
            session_id: session['session_id'],
            csrf_token: session['_csrf_token'],
            warden_user: processed_warden
          }

          # Captura chaves do Devise Masquerade (caso esteja personificando outro usuário)
          masquerade_keys = session.keys.select { |key| key.to_s.start_with?('devise_masquerade_') }
          masquerade_data = masquerade_keys.each_with_object({}) do |key, hash|
            hash[key] = session[key]
          end

          masquerade_data = {'masquerade_data': masquerade_data}

          # Junta os dados da sessão com os de masquerading
          session_info.merge!(masquerade_data).compact
        end

        # Captura as mensagens flash
        def fetch_flash_messages(env)
          flash_hash = env['action_dispatch.request.flash_hash']
          return {} unless flash_hash

          {
            notice: flash_hash[:notice],
            alert: flash_hash[:alert]
          }.compact
        end

        # Gera o script que será injetado no HTML
        def generate_script(config:, dsn:, user_data:, session_data:, flash_messages:, request_params:)
          <<~SCRIPT
            <script src="/assets/haystack/bundle.tracing.replay.min.js"></script>
            <script >
              Haystack.init({
                dsn: "#{dsn}",
                replaysSessionSampleRate: #{config.js.replays_session_sample_rate || 0},
                replaysOnErrorSampleRate: #{config.js.replays_on_error_sample_rate || 1},
                environment: "#{config.js.environment || ::Rails.env}",
                tracesSampleRate: #{config.js.traces_sample_rate || 1},
                integrations: [
                  Haystack.replayIntegration({
                    maskAllText: #{config.js.mask_all_text.nil? ? false : config.js.mask_all_text},
                    blockAllMedia: #{config.js.block_all_media.nil? ? true : config.js.block_all_media},
                  }),
                  Haystack.browserTracingIntegration(),
                ]
              });

              #{user_data.any? ? "Haystack.setUser(#{user_data.to_json.html_safe});" : ""}

              #{session_data.any? ? "Haystack.setContext('session', #{session_data.to_json.html_safe});" : ""}

              #{flash_messages.any? ? "Haystack.setContext('flash_messages', #{flash_messages.to_json.html_safe});" : ""}

              #{request_params.any? ? "Haystack.setContext('request_params', #{request_params.to_json.html_safe});" : ""}
            </script>
          SCRIPT
        end
      end
    end
  end
end
