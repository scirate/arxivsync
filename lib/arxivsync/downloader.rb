module ArxivSync
  class Downloader
    def initialize(initial_params={})
      @initial_params = initial_params

      if @initial_params[:from] == Date.today
        puts "Last responseDate was today. arXiv lacks date granularity beyond the day level; please wait before continuing harvest.".light_yellow
        return false
      end

      unless @initial_params[:resumptionToken]
        @initial_params[:metadataPrefix] ||= 'arXivRaw'
      end
      @last_params = nil

      domain = ENV['ARXIV_EXPORT_DOMAIN'] || "export.arxiv.org"
      @oai = OAI::Client.new("http://#{domain}/oai2")
    end

    def start(&b)
      # Make the initial request
      resp = make_request(@initial_params)

      # Continue to make requests until the server stops sending
      # resumption tokens
      while true
        if !resp.resumption_token || resp.resumption_token.empty?
          if resp.doc.to_s.include?("Retry after 20 seconds") # Rate limitation
            puts "Honoring 503 and sleeping for 20 seconds...".light_yellow
            sleep 20
            resp = retry_request
          else # No resumption_token and no retry should mean we're finished
            b.call(resp)
            puts "Finished archiving~!".bold.light_green
            break
          end
        else # We have a resumption_token, keep going!
          sleep 20 # let's be extra cautious though
          b.call(resp)
          resp = make_request(resumptionToken: resp.resumption_token)
        end
      end

      return self
    end

    def retry_request
      make_request(@last_params)
    end

    def make_request(params)
      puts "Making OAI request with params: #{params.inspect}".light_magenta

      @last_params = params.clone # list_records will nuke our params

      begin
        return @oai.list_records(params)
      rescue Faraday::TimeoutError
        puts "Request timed out; retrying in 20 seconds".light_yellow
        sleep 20
        return retry_request
      end
    end
  end
end
