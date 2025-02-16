#include "eventsub.hpp"
#include <iostream>
#include <chrono>
#include <functional>
#include <atomic>
#include <memory>
#include <boost/asio.hpp>
#include <boost/beast.hpp>
#include <boost/beast/websocket.hpp>
#include <json/json.h>
//----------------------------------------------------------
using namespace boost::asio;
using namespace boost::beast;

//----------------------------------------------------------
constexpr std::string_view EVENTSUB_WEBSOCKET_URL       = "wss://eventsub.wss.twitch.tv/ws";
constexpr std::string_view EVENTSUB_HOST                = "eventsub.wss.twitch.tv";
constexpr std::string_view EVENTSUB_PORT                = "443";
constexpr std::string_view BET_LIMIT_WARNING            = "Bet exceeds limit! Max: ";
constexpr std::string_view EVENTSUB_TYPE_NOTIFICATION   = "notification";
constexpr std::string_view EVENTSUB_BET_EVENT           = "channel.channel_points_custom_reward_redemption.add";
//----------------------------------------------------------
static io_context ioc;
static websocket::stream<tcp::socket> ws(ioc);
static boost::asio::steady_timer reconnect_timer(ioc);

static size_t max_bet_limit         = 5000UL;  // Default bet limit
static size_t bet_timeout_duration  = 30UL;  // Default timeout in seconds
static std::string websocket_url    = std::string(DEFAULT_WEBSOCKET_URL);
//--------------------------
static std::atomic<bool> is_connected{false};
static std::function<void(std::string_view, size_t)> overlay_callback;
static std::function<void(bool)> status_callback;
//----------------------------------------------------------
// Helper functions 
//--------------------------
// Async Connection Handler
//--------------------------
void handle_connect(boost::system::error_code ec) {
    if (ec) {
        std::cerr << "Error connecting to Twitch EventSub: " << ec.message() << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(5)); // Retry after delay
        EventSub::async_connect();
        return;
    }

    ws.async_handshake(EVENTSUB_HOST.data(), EVENTSUB_WEBSOCKET_URL.data(),
        [](boost::system::error_code ec) {
            if (ec) {
                std::cerr << "WebSocket Handshake Failed: " << ec.message() << std::endl;
                return;
            }
            
            notify_status(true);
            obs_log_info("Connected to Twitch EventSub!");
            EventSub::async_listenForBets();
        }
    );
}
//----------------------------------------------------------
// Async Resolve Handler
//--------------------------
void handle_resolve(const boost::system::error_code& ec, tcp::resolver::results_type results) {
    if (ec) {
        std::cerr << "Failed to resolve Twitch EventSub host: " << ec.message() << std::endl;
        return;
    }

    ws.next_layer().async_connect(*results.begin(), &handle_connect);
}
//----------------------------------------------------------
// Async Read Handler
//--------------------------
void handle_read(boost::system::error_code ec, std::size_t bytes_transferred, flat_buffer& buffer) {
    if (ec) {
        std::cerr << "WebSocket Read Error: " << ec.message() << std::endl;
        EventSub::notify_status(false);
        EventSub::async_connect(); // **Trigger immediate reconnect**
        return;
    }

    std::string_view response = buffers_to_string(buffer.data());
    Json::Value jsonResponse;
    Json::CharReaderBuilder builder;
    std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    std::string errors;

    if (!reader->parse(response.data(), response.data() + response.size(), &jsonResponse, &errors)) {
        std::cerr << "Failed to parse Twitch EventSub response: " << errors << std::endl;
        return;
    }

    if (jsonResponse["type"].asString() != EVENTSUB_TYPE_NOTIFICATION) return;
    if (jsonResponse["subscription"]["type"].asString() != EVENTSUB_BET_EVENT) return;

    size_t betAmount = static_cast<size_t>(jsonResponse["event"]["reward"]["cost"].asUInt());
    if (custom_bet_limit_enabled && betAmount > max_bet_limit) {
        notify_overlay(BET_LIMIT_WARNING.data() + std::to_string(max_bet_limit), bet_timeout_duration);
    }

    buffer.consume(bytes_transferred);  // Clear buffer after read
    ws.async_read(buffer, std::bind(&handle_read, std::placeholders::_1, std::placeholders::_2, std::ref(buffer)));
}
//----------------------------------------------------------
// Periodic WebSocket Health Check
//--------------------------
void check_connection_status(const boost::system::error_code& ec) {
    if (ec) {
        return;
    }

    if (!is_connected.load()) {
        std::cerr << "WebSocket Disconnected! Attempting reconnect..." << std::endl;
        EventSub::async_connect();
    }

    reconnect_timer.expires_after(std::chrono::seconds(10));
    reconnect_timer.async_wait(&check_connection_status);
}
//----------------------------------------------------------
void EventSub::initialize(void) {
    std::thread([]() { ioc.run(); }).detach();

    reconnect_timer.expires_after(std::chrono::seconds(10));
    reconnect_timer.async_wait(&check_connection_status);

    async_connect();
}

void EventSub::shutdown(void) {
    ws.close(websocket::close_code::normal);
    notify_status(false);
    obs_log_info("EventSub connection closed.");
}

void EventSub::async_connect() {
    obs_log_info("Connecting to WebSocket: %s", websocket_url.c_str());
    // resolver.async_resolve(websocket_url, EVENTSUB_PORT.data() , &handle_resolve);
    resolver.async_resolve(EVENTSUB_HOST.data(), EVENTSUB_PORT.data(), 
        [](const boost::system::error_code& ec, tcp::resolver::results_type results) {
            if (!ec) {
                ws.next_layer().async_connect(*results.begin(), &handle_connect);
            } else {
                std::cerr << "Failed to resolve host: " << ec.message() << std::endl;
            }
        }
    );
}

void EventSub::set_max_bet_limit(const size_t& limit) {
    max_bet_limit = limit;
    obs_log_info("New Max Bet Limit: %zu", max_bet_limit);
}

void EventSub::set_bet_timeout_duration(const size_t& duration) {
    bet_timeout_duration = duration;
    obs_log_info("New Bet Timeout Duration: %zu seconds", bet_timeout_duration);
}

void EventSub::set_overlay_callback(std::function<void(std::string_view, size_t)> callback) {
    overlay_callback = std::move(callback);
}

void EventSub::set_status_callback(std::function<void(bool)> callback) {
    status_callback = std::move(callback);
}

// Start Async Listening
void EventSub::async_listenForBets() {
    if (!ws.is_open()) (
        return;
    )
    flat_buffer buffer;
    ws.async_read(buffer, std::bind(&handle_read, std::placeholders::_1, std::placeholders::_2, std::ref(buffer)));
}

void EventSub::notify_overlay(std::string_view message, size_t duration) {
    if (overlay_callback) {
        overlay_callback(message, duration);
    }
}

void EventSub::notify_status(bool connected) {
    is_connected.store(connected);
    if (status_callback) {
        status_callback(is_connected.load()); // Call UI function
    }
}