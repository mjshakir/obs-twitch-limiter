#include "eventsub.hpp"
#include <thread>
#include <chrono>
#include <limits>
#include <regex>
#include <algorithm>
#include <rapidjson/document.h>
#include <obs-module.h>
#include <obs.h>
//--------------------------------------------------------------
// Definition
//--------------------------------------------------------------
constexpr std::string_view EVENTSUB_WEBSOCKET_URL = "wss://eventsub.wss.twitch.tv/ws";
constexpr std::string_view EVENTSUB_PORT = "443";
constexpr std::string_view BET_LIMIT_WARNING = "Bet exceeds limit! Max: ";
constexpr std::string_view EVENTSUB_TYPE_NOTIFICATION = "notification";
constexpr std::string_view EVENTSUB_BET_EVENT = "channel.channel_points_custom_reward_redemption.add";
constexpr size_t MAX_RECONNECT_DELAY = 24UL * 60UL * 60UL; // 24 hours in seconds
constexpr size_t DEFAULT_MAX_BET_LIMIT = 5000UL;
constexpr size_t DEFAULT_BET_TIMEOUT = 30UL;
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
	  m_max_bet_limit(DEFAULT_MAX_BET_LIMIT),
	  m_bet_timeout_duration(DEFAULT_BET_TIMEOUT),
	  m_reconnect_attempts(0UL),
	  m_websocket_url(std::make_shared<std::string>(std::string(EVENTSUB_WEBSOCKET_URL))),
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
	blog(LOG_INFO, "EventSub connection initializing...");
	std::thread([this]() { this->m_io_context.run(); }).detach();

	m_reconnect_timer.expires_after(std::chrono::seconds(10));
	m_reconnect_timer.async_wait(
		[this](const boost::system::error_code &ec) { this->check_connection_status(ec); });

	async_connect();
	blog(LOG_INFO, "EventSub connection initialized.");
}

// **🔹 Shutdown WebSocket Connection**
void EventSub::shutdown(void)
{
	blog(LOG_INFO, "EventSub connection closed.");
	if (m_connected.load()) {
		m_websocket.close(boost::beast::websocket::close_code::normal);
		notify_status(false);
	}
}

// **🔹 Set Max Bet Limit**
void EventSub::set_max_bet_limit(const size_t &limit)
{
	m_max_bet_limit.store(limit);
	blog(LOG_INFO, "New Bet Timeout Duration: %zu seconds", limit);
}

void EventSub::set_max_bet_limit(bool enable, const size_t &limit)
{
	m_max_bet_limit.store(enable ? limit : std::numeric_limits<size_t>::max());
	blog(LOG_INFO, "New Bet Timeout Duration: %zu seconds", limit);
}

void EventSub::set_max_bet_limit(bool enable)
{
	m_max_bet_limit.store(enable ? m_max_bet_limit.load() : std::numeric_limits<size_t>::max());
	blog(LOG_INFO, "New Bet Timeout Duration: %zu seconds", m_max_bet_limit.load());
}

// **🔹 Set Bet Timeout Duration**
void EventSub::set_bet_timeout_duration(const size_t &duration)
{
	m_bet_timeout_duration.store(duration);
	blog(LOG_INFO, "New Bet Timeout Duration: %zu seconds", duration);
}

void EventSub::set_websocket_url(std::string_view url)
{
	if (url.empty() or !valid_websocket_url(url)) {
		m_websocket_url.store(std::make_shared<std::string>(std::string(EVENTSUB_WEBSOCKET_URL)));
		blog(LOG_INFO, "WebSocket URL reset to default: %s", m_websocket_url.load()->c_str());
	} else {
		m_websocket_url.store(std::make_shared<std::string>(std::string(url)));
		blog(LOG_INFO, "WebSocket URL updated: %s", m_websocket_url.load()->c_str());
	}

	// If already connected, reconnect with the new URL
	if (m_connected.load()) {
		blog(LOG_INFO, "Reconnecting with new WebSocket URL...");
		shutdown();
		async_connect();
	}
}
void EventSub::set_websocket_url(void)
{
	set_websocket_url(std::string_view());
}

size_t EventSub::get_max_bet_limit(void) const
{
	return m_max_bet_limit.load();
}
size_t EventSub::get_bet_timeout_duration(void) const
{
	return m_bet_timeout_duration.load();
}

std::string EventSub::get_websocket_url(void) const
{
	return *m_websocket_url.load();
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
void EventSub::notify_overlay(std::string_view message, size_t duration) const
{
	if (m_overlay_callback) {
		m_overlay_callback(message, duration);
	}
}

// **🔹 Async WebSocket Connection**
void EventSub::async_connect(void)
{
	if (!valid_websocket_url(m_websocket_url.load())) {
		blog(LOG_ERROR, "Invalid WebSocket URL: %s. Resetting to default.", m_websocket_url.load().c_str());
		set_websocket_url();
	}

	if (m_reconnect_attempts.load() >= MAX_RECONNECT_DELAY) {
		blog(LOG_ERROR, "Max reconnect time (24 hours) reached. Manual reconnect required.");
		return;
	}

	const size_t delay = std::min<size_t>(5 * (1 << m_reconnect_attempts.load()),
					      MAX_RECONNECT_DELAY); // Exponential backoff (5s * 2^n)

	blog(LOG_INFO, "Attempting WebSocket reconnect (Attempt %zu), waiting %zu seconds",
	     m_reconnect_attempts.load() + 1, delay);

	safe_increment();

	// Uses `m_reconnect_timer` to delay the connection attempt
	m_reconnect_timer.expires_after(std::chrono::seconds(delay));
	m_reconnect_timer.async_wait([this](const boost::system::error_code &) {
		blog(LOG_INFO, "Resolving WebSocket URL: %s", m_websocket_url.load()->c_str());
		// Uses `m_resolver` to resolve Twitch's EventSub WebSocket server
		m_resolver.async_resolve(*m_websocket_url.load(), EVENTSUB_PORT.data(),
					 [this](const boost::system::error_code &ec,
						boost::asio::ip::tcp::resolver::results_type results) {
						 if (!ec) {
							 m_websocket.next_layer().async_connect(
								 *results.begin(),
								 [this](const boost::system::error_code &ec) {
									 handle_connect(ec);
								 });
						 } else {
							 blog(LOG_ERROR, "Failed to resolve Twitch EventSub host: %s",
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
		blog(LOG_ERROR, "Failed to resolve Twitch EventSub host: %s", ec.message().c_str());
		return;
	}
	m_websocket.next_layer().async_connect(*results.begin(), [this](const boost::system::error_code &ec) {
		this->handle_connect(ec);
	});
}

// **🔹 Async WebSocket Connection Handler**
void EventSub::handle_connect(const boost::system::error_code &ec)
{
	if (ec) {
		blog(LOG_ERROR, "WebSocket Connection Failed: %s", ec.message().c_str());
		std::this_thread::sleep_for(std::chrono::seconds(5));
		async_connect();
		return;
	}

	auto parsed_url = parse_websocket_url(*m_websocket_url.load());
	if (!parsed_url) {
		blog(LOG_ERROR, "WebSocket connection aborted due to invalid URL.");
		return;
	}

	const auto [host, path] = parsed_url.value();
	blog(LOG_INFO, "Connecting WebSocket: Host=%s, Path=%s", host.c_str(), path.c_str());

	m_websocket.async_handshake(host, path, [this](const boost::system::error_code &ec) {
		if (ec) {
			blog(LOG_ERROR, "WebSocket Handshake Failed: %s", ec.message().c_str());
			return;
		}

		blog(LOG_INFO, "Connected to Twitch EventSub!");
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

	m_websocket.async_read(m_buffer, [this](const boost::system::error_code &ec, const size_t &bytes_transferred) {
		this->handle_read(ec, bytes_transferred, m_buffer);
	});
}

// **🔹 Async WebSocket Read Handler**
void EventSub::handle_read(const boost::system::error_code &ec, const size_t &bytes_transferred,
			   boost::beast::flat_buffer &buffer)
{
	if (ec) {
		blog(LOG_ERROR, "WebSocket Read Error: %s", ec.message().c_str());
		notify_status(false);
		async_connect(); // Attempt to reconnect on failure
		return;
	}

	std::string response = boost::beast::buffers_to_string(buffer.data());

	buffer.consume(bytes_transferred);

	rapidjson::Document jsonResponse;
	if (jsonResponse.Parse(response.data()).HasParseError()) {
		blog(LOG_ERROR, "Failed to parse Twitch EventSub response");
		async_listenForBets(); // Keep listening even if parsing fails
		return;
	}

	if (!jsonResponse.HasMember("type") or !jsonResponse["type"].IsString()) {
		blog(LOG_ERROR, "Invalid response: Missing type field");
		async_listenForBets(); // Continue listening
		return;
	}

	if (jsonResponse["type"].GetString() == std::string(EVENTSUB_TYPE_NOTIFICATION) and
	    jsonResponse["subscription"]["type"].GetString() == std::string(EVENTSUB_BET_EVENT)) {

		if (jsonResponse.HasMember("event") and jsonResponse["event"].HasMember("reward") and
		    jsonResponse["event"]["reward"].HasMember("cost") and
		    jsonResponse["event"]["reward"]["cost"].IsUint()) {

			const size_t bet_amount = jsonResponse["event"]["reward"]["cost"].GetUint();
			if (bet_amount > m_max_bet_limit.load()) {
				notify_overlay(BET_LIMIT_WARNING.data() + std::to_string(m_max_bet_limit.load()),
					       m_bet_timeout_duration.load());
			}
		} else {
			blog(LOG_ERROR, "Invalid bet event structure");
		}
	}

	async_listenForBets();
}

void EventSub::check_connection_status(const boost::system::error_code &ec)
{
	if (ec) {
		return;
	}

	if (!m_connected.load()) {
		blog(LOG_ERROR, "WebSocket Disconnected! Attempting reconnect...");
		EventSub::async_connect();
	}

	m_reconnect_timer.expires_after(std::chrono::seconds(10));
	m_reconnect_timer.async_wait(
		[this](const boost::system::error_code &ec) { this->check_connection_status(ec); });
}

void EventSub::safe_increment(void)
{
	if (m_reconnect_attempts.load() < std::numeric_limits<size_t>::max()) {
		m_reconnect_attempts++;
	}
}

bool EventSub::valid_websocket_url(std::string_view url) const
{
	constexpr std::string_view WS_URL_REGEX_PATTERN = R"(^wss:\/\/[a-zA-Z0-9.-]+(:[0-9]+)?\/?.*$)";
	static const std::regex ws_regex(WS_URL_REGEX_PATTERN.data());
	return std::regex_match(url.begin(), url.end(), ws_regex);
}

std::optional<std::pair<std::string, std::string>> EventSub::parse_websocket_url(std::string_view url) const
{
	constexpr std::string_view WSS_SCHEME = "wss://";
	constexpr std::string_view HTTP_SCHEME = "http://";
	constexpr std::string_view HTTPS_SCHEME = "https://";
	constexpr std::string_view FTP_SCHEME = "ftp://";

	const size_t scheme_end = url.find("://");
	if (scheme_end == std::string_view::npos) {
		blog(LOG_ERROR, "Invalid WebSocket URL (missing scheme): %s", url.data());
		return std::nullopt;
	}

	std::string_view scheme = url.substr(0, scheme_end + 3);

	if (scheme != WSS_SCHEME and scheme != HTTP_SCHEME and scheme != HTTPS_SCHEME and scheme != FTP_SCHEME) {
		blog(LOG_ERROR, "Unsupported URL scheme: %s", scheme.data());
		return std::nullopt;
	}

	auto host_start = url.begin() + scheme.size();
	auto path_start = std::find(host_start, url.end(), '/');

	std::string host(host_start, path_start);

	std::string path = (path_start != url.end()) ? std::string(path_start, url.end()) : "/";

	blog(LOG_INFO, "Parsed WebSocket URL -> Scheme: [%s], Host: [%s], Path: [%s]", scheme.data(), host.c_str(),
	     path.c_str());

	return std::make_pair(std::move(host), std::move(path));
}