#include "eventsub.hpp"
#include <thread>
#include <rapidjson/document.h>
#include <obs.h>
//--------------------------------------------------------------
// Definition
//--------------------------------------------------------------
constexpr std::string_view EVENTSUB_WEBSOCKET_URL = "wss://eventsub.wss.twitch.tv/ws";
constexpr std::string_view EVENTSUB_HOST = "eventsub.wss.twitch.tv";
constexpr std::string_view EVENTSUB_PORT = "443";
constexpr std::string_view BET_LIMIT_WARNING = "Bet exceeds limit! Max: ";
constexpr std::string_view EVENTSUB_TYPE_NOTIFICATION = "notification";
constexpr std::string_view EVENTSUB_BET_EVENT = "channel.channel_points_custom_reward_redemption.add";
constexpr size_t MAX_RECONNECT_DELAY = 24UL * 60UL * 60UL; // 24 hours in seconds
//--------------------------------------------------------------
// **🔹 Singleton Instance**
EventSub &EventSub::instance(void)
{
	static EventSub instance;
	return instance;
}

// **🔹 Constructor & Destructor**
EventSub::EventSub(void)
	: m_connected(false),
	  m_max_bet_limit(5000UL),
	  m_bet_timeout_duration(30UL),
	  m_reconnect_attempts(0UL),
	  m_websocket_url(std::string(EVENTSUB_WEBSOCKET_URL)),
	  m_io_context(),
	  m_resolver(m_io_context),
	  m_websocket(m_io_context),
	  m_reconnect_timer(m_io_context),
	  m_buffer()
{
	m_work_guard.emplace(m_io_context.get_executor());
}

EventSub::~EventSub(void)
{
	shutdown();
	m_work_guard.reset();
}

// **🔹 Initialize WebSocket Connection**
void EventSub::initialize(void)
{
	obs_log_info("EventSub connection initializing...");
	std::thread([]() { m_io_context.run(); }).detach();

	m_reconnect_timer.expires_after(std::chrono::seconds(10));
	m_reconnect_timer.async_wait(&check_connection_status);

	async_connect();
	obs_log_info("EventSub connection initialized.");
}

// **🔹 Shutdown WebSocket Connection**
void EventSub::shutdown(void)
{
	obs_log_info("EventSub connection closed.");
	if (m_connected.load()) {
		m_websocket.close(boost::beast::websocket::close_code::normal);
		notify_status(false);
	}
}

// **🔹 Set Max Bet Limit**
void EventSub::set_max_bet_limit(const size_t &limit)
{
	m_max_bet_limit.store(limit);
	obs_log_info("New Bet Timeout Duration: %zu seconds", bet_timeout_duration);
}

// **🔹 Set Bet Timeout Duration**
void EventSub::set_bet_timeout_duration(const size_t &duration)
{
	m_bet_timeout_duration.store(duration);
	obs_log_info("New Bet Timeout Duration: %zu seconds", bet_timeout_duration);
}

// **🔹 Set OBS Callbacks**
void EventSub::set_overlay_callback(std::function<void(std::string_view, size_t)> callback)
{
	m_overlay_callback = std::move(callback);
}

void EventSub::set_status_callback(std::function<void(bool)> callback)
{
	m_status_callback = std::move(callback);
}

// **🔹 Notify OBS of WebSocket Status**
void EventSub::notify_status(bool connected)
{
	m_connected.store(connected);
	if (m_status_callback) {
		m_status_callback(connected);
	}
}

// **🔹 Notify OBS to Show Overlay**
void EventSub::notify_overlay(std::string_view message, size_t duration)
{
	if (m_overlay_callback) {
		m_overlay_callback(message, duration);
	}
}

// **🔹 Async WebSocket Connection**
void EventSub::async_connect(void)
{
	if (m_reconnect_attempts.load() >= MAX_RECONNECT_DELAY) {
		obs_log_error("Max reconnect time (24 hours) reached. Manual reconnect required.");
		return;
	}

	size_t delay = std::min<size_t>(5 * (1 << m_reconnect_attempts.load()),
					MAX_RECONNECT_DELAY); // Exponential backoff (5s * 2^n)

	obs_log_info("Attempting WebSocket reconnect (Attempt %zu), waiting %zu seconds",
		     m_reconnect_attempts.load() + 1, delay);

	m_reconnect_attempts++;

	// Uses `m_reconnect_timer` to delay the connection attempt
	m_reconnect_timer.expires_after(std::chrono::seconds(delay));
	m_reconnect_timer.async_wait([this](const boost::system::error_code &) {
		// Uses `m_resolver` to resolve Twitch's EventSub WebSocket server
		m_resolver.async_resolve(
			EVENTSUB_HOST.data(), EVENTSUB_PORT.data(),
			[this](const boost::system::error_code &ec, tcp::resolver::results_type results) {
				if (!ec) {
					m_websocket.next_layer().async_connect(
						*results.begin(),
						[this](const boost::system::error_code &ec) { handle_connect(ec); });
				} else {
					obs_log_error("Failed to resolve Twitch EventSub host: %s",
						      ec.message().c_str());
					async_connect(); // Retry on failure
				}
			});
	});
}

// **🔹 Async Resolve Handler**
void EventSub::handle_resolve(const boost::system::error_code &ec, boost::asio::ip::tcp::resolver::results_type results)
{
	if (ec) {
		obs_log_error("Failed to resolve Twitch EventSub host: %s", ec.message().c_str());
		return;
	}
	m_websocket.next_layer().async_connect(*results.begin(),
					       [this](const boost::system::error_code &ec) { handle_connect(ec); });
}

// **🔹 Async WebSocket Connection Handler**
void EventSub::handle_connect(const boost::system::error_code &ec)
{
	if (ec) {
		obs_log_error("WebSocket Connection Failed: %s", ec.message().c_str());
		std::this_thread::sleep_for(std::chrono::seconds(5));
		async_connect();
		return;
	}
	m_websocket.async_handshake(EVENTSUB_HOST.data(), "/ws", [this](const boost::system::error_code &ec) {
		if (ec) {
			obs_log_error("WebSocket Handshake Failed: %s", ec.message().c_str());
			return;
		}

		obs_log_info("Connected to Twitch EventSub!");
		m_reconnect_attempts.store(0UL); // Reset the counter
		notify_status(true);
		async_listenForBets();
	});
}

// **🔹 Async WebSocket Listener**
void EventSub::async_listenForBets(void)
{
	if (!m_websocket.is_open()) {
		return;
	}

	m_websocket.async_read(*m_buffer, [this](const boost::system::error_code &ec, size_t bytes_transferred) {
		handle_read(ec, bytes_transferred, *m_buffer);
	});
}

// **🔹 Async WebSocket Read Handler**
void EventSub::handle_read(const boost::system::error_code &ec, size_t bytes_transferred,
			   boost::beast::flat_buffer &buffer)
{
	if (ec) {
		obs_log_error("WebSocket Read Error: %s", ec.message().c_str());
		notify_status(false);
		async_connect(); // Attempt to reconnect on failure
		return;
	}

	std::string_view response = boost::beast::buffers_to_string(buffer.data());
	buffer.consume(bytes_transferred);

	rapidjson::Document jsonResponse;
	if (jsonResponse.Parse(response.data()).HasParseError()) {
		obs_log_error("Failed to parse Twitch EventSub response");
		async_listenForBets(); // Keep listening even if parsing fails
		return;
	}

	if (!jsonResponse.HasMember("type") || !jsonResponse["type"].IsString()) {
		obs_log_error("Invalid response: Missing type field");
		async_listenForBets(); // Continue listening
		return;
	}

	if (jsonResponse["type"].GetString() == std::string(EVENTSUB_TYPE_NOTIFICATION) &&
	    jsonResponse["subscription"]["type"].GetString() == std::string(EVENTSUB_BET_EVENT)) {

		if (jsonResponse.HasMember("event") && jsonResponse["event"].HasMember("reward") &&
		    jsonResponse["event"]["reward"].HasMember("cost") &&
		    jsonResponse["event"]["reward"]["cost"].IsUint()) {

			size_t betAmount = jsonResponse["event"]["reward"]["cost"].GetUint();
			if (betAmount > m_max_bet_limit.load()) {
				notify_overlay(BET_LIMIT_WARNING.data() + std::to_string(m_max_bet_limit.load()),
					       m_bet_timeout_duration.load());
			}
		} else {
			obs_log_error("Invalid bet event structure");
		}
	}

	async_listenForBets();
}

void EventSub::check_connection_status(const boost::system::error_code &ec)
{
	if (ec) {
		return;
	}

	if (!is_connected.load()) {
		obs_log_error("WebSocket Disconnected! Attempting reconnect...");
		EventSub::async_connect();
	}

	m_reconnect_timer.expires_after(std::chrono::seconds(10));
	m_reconnect_timer.async_wait(&check_connection_status);
}