require "functions_framework"
require "faraday"
require "faraday/retry"
require "json"

# Inizializza il client Twilio una sola volta per ottimizzare il cold start
# I segreti sono caricati come variabili d'ambiente (es. da Secret Manager)
TWILIO_ACCOUNT_SID = ENV["TWILIO_ACCOUNT_SID"]
TWILIO_AUTH_TOKEN  = ENV["TWILIO_AUTH_TOKEN"]
TWILIO_FROM_NUMBER = ENV["TWILIO_FROM_NUMBER"]

# URL base per l'invio SMS
TWILIO_URL = "https://api.twilio.com/2010-04-01/Accounts/#{TWILIO_ACCOUNT_SID}/Messages.json"

FunctionsFramework.http "send_sms" do |request|
  begin
    # 1. Parsing della richiesta
    payload = JSON.parse(request.body.read)
    to_number = payload["to"]
    message_body = payload["body"]

    # Validazione base
    if to_number.nil? || message_body.nil?
      return { error: "Missing 'to' or 'body' parameters" }.to_json
    end

    if [TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER].any?(&:nil?)
      FunctionsFramework.logger.error "Missing Twilio configuration secrets!"
      return { error: "Service misconfiguration" }.to_json
    end

    # 2. Invio SMS con Faraday
    conn = Faraday.new(url: TWILIO_URL) do |f|
      f.request :url_encoded
      f.request :authorization, :basic, TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN
      
      # Retry automatico se l'API di Twilio flappa (resilienza)
      f.request :retry, max: 2, interval: 0.1, backoff_factor: 2
      
      f.adapter Faraday.default_adapter
    end

    response = conn.post do |req|
      req.body = {
        "To" => to_number,
        "From" => TWILIO_FROM_NUMBER,
        "Body" => message_body
      }
    end

    # 3. Gestione Risposta
    if response.success?
      twilio_resp = JSON.parse(response.body)
      { status: "success", sid: twilio_resp["sid"] }.to_json
    else
      FunctionsFramework.logger.error "Twilio Error: #{response.status} - #{response.body}"
      # Non esporre dettagli interni all'utente finale, loggali e basta
      { status: "error", code: response.status, message: "Failed to send SMS" }.to_json
    end

  rescue JSON::ParserError => e
    return { error: "Invalid JSON payload" }.to_json
  rescue => e
    FunctionsFramework.logger.error "Unexpected error: #{e.message}"
    return { error: "Internal Server Error" }.to_json
  end
end
