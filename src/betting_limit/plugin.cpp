#include "plugin.hpp"
#include <obs-properties.h>
#include <obs-module.h>
#include <obs-frontend-api.h>
#include "eventsub.hpp"
#include <memory>
#include <thread>
#include <regex>
#include <chrono>
#include <string>
#include <boost/asio.hpp>
#include <boost/asio/steady_timer.hpp>

// Default values
static constexpr size_t DEFAULT_MAX_BET_LIMIT = 5000UL;
static constexpr size_t DEFAULT_BET_TIMEOUT = 30UL;
static constexpr std::string_view DEFAULT_WEBSOCKET_URL = "wss://eventsub.wss.twitch.tv/ws";
static constexpr std::string_view WS_URL_REGEX_PATTERN = R"(^wss:\/\/[a-zA-Z0-9.-]+(:[0-9]+)?\/?.*$)";

static size_t max_bet_limit = DEFAULT_MAX_BET_LIMIT;
static size_t bet_timeout_duration = DEFAULT_BET_TIMEOUT;
static std::string websocket_url = std::string(DEFAULT_WEBSOCKET_URL);
static bool custom_bet_limit_enabled = true; // Default: Enabled
static boost::asio::io_context overlay_io_context;
static boost::asio::steady_timer overlay_timer(overlay_io_context);

// Smart pointer for overlay management
std::unique_ptr<obs_source_t, decltype(&obs_source_release)> overlay_source(nullptr, &obs_source_release);

// Show overlay with timeout
void show_overlay_notification(std::string_view message, size_t duration)
{
	std::unique_ptr<obs_data_t, decltype(&obs_data_release)> settings(obs_data_create(), &obs_data_release);
	obs_data_set_string(settings.get(), "text", message.data());

	if (!overlay_source) {
		overlay_source.reset(obs_source_create("text_gdiplus", "Bet Limit Warning", settings.get(), nullptr));
	} else {
		obs_source_update(overlay_source.get(), settings.get());
	}

	// Set timer to auto-hide overlay
	overlay_timer.expires_after(std::chrono::seconds(duration));
	overlay_timer.async_wait([](const boost::system::error_code &) { hide_overlay_notification(); });

	// Start Boost.Asio event loop in background
	std::thread([] { overlay_io_context.run(); }).detach();
}

// Hide overlay
void hide_overlay_notification(void)
{
	overlay_source.reset(); // Smart pointer handles cleanup
	overlay_timer.cancel();
}

bool reset_overlay(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);
	hide_overlay_notification();
	obs_log_info("Overlay manually reset by user.");
	return true;
}

// OBS Plugin Load
bool obs_module_load(void)
{
	obs_log_info("Twitch Betting Limit Plugin Loaded.");
	EventSub::instance().set_status_callback(update_websocket_status);
	EventSub::instance().set_overlay_callback(show_overlay_notification);
	EventSub::instance().initialize();
	return true;
}

// OBS Plugin Unload
void obs_module_unload(void)
{
	hide_overlay_notification();
	EventSub::instance().shutdown();
}

// OBS Settings UI
obs_properties_t *obs_module_get_settings(void *data)
{
	static_cast<void>(data);
	std::unique_ptr<obs_properties_t, decltype(&obs_properties_destroy)> props(obs_properties_create(),
										   &obs_properties_destroy);

	obs_property_t *limit_toggle =
		obs_properties_add_bool(props.get(), "enable_custom_bet_limit", "Enable Custom Bet Limit");
	obs_property_set_modified_callback(limit_toggle,
					   [](obs_properties_t *, obs_property_t *, obs_data_t *) -> bool {
						   return toggle_custom_bet_limit(nullptr, nullptr, nullptr);
					   });

	static_cast<void>(obs_properties_add_int(props.get(), "max_bet_limit", "Max Bet Limit", 100, 100000, 100));
	static_cast<void>(obs_properties_add_int(props.get(), "bet_timeout_duration", "Bet Timeout Duration (seconds)",
						 5, 300, 5));

	static_cast<void>(
		obs_properties_add_button(props.get(), "reset_bet_limit", "Reset Bet Limit", reset_bet_limit));
	static_cast<void>(
		obs_properties_add_button(props.get(), "reset_bet_timeout", "Reset Bet Timeout", reset_bet_timeout));
	static_cast<void>(obs_properties_add_button(props.get(), "reset_overlay", "Reset Overlay", reset_overlay));

	obs_property_t *ws_url_prop =
		obs_properties_add_text(props.get(), "websocket_url", "WebSocket URL", OBS_TEXT_DEFAULT);
	obs_property_set_modified_callback(ws_url_prop, validate_websocket_url);

	static_cast<void>(obs_properties_add_button(props.get(), "reset_websocket_url", "Reset WebSocket URL",
						    reset_websocket_url));

	static_cast<void>(obs_properties_add_button(props.get(), "manual_reconnect_eventsub",
						    "Reconnect to Twitch EventSub", manual_reconnect_eventsub));

	obs_property_t *ws_status =
		obs_properties_add_text(props.get(), "ws_status", "WebSocket Status", OBS_TEXT_INFO);
	obs_property_set_enabled(ws_status, false); // Read-only field

	return props.release();
}

// Reset only Bet Limit
bool reset_bet_limit(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);
	std::unique_ptr<obs_data_t, decltype(&obs_data_release)> settings(obs_data_create(), &obs_data_release);
	obs_data_set_int(settings.get(), "max_bet_limit", DEFAULT_MAX_BET_LIMIT);

	obs_module_update_settings(settings.get());

	obs_log_info("Reset Bet Limit to default: %d", DEFAULT_MAX_BET_LIMIT);
	return true;
}

// Reset only Bet Timeout
bool reset_bet_timeout(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);
	std::unique_ptr<obs_data_t, decltype(&obs_data_release)> settings(obs_data_create(), &obs_data_release);
	obs_data_set_int(settings.get(), "bet_timeout_duration", DEFAULT_BET_TIMEOUT);

	obs_module_update_settings(settings.get());

	obs_log_info("Reset Bet Timeout to default: %d seconds", DEFAULT_BET_TIMEOUT);
	return true;
}

bool manual_reconnect_eventsub(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);
	obs_log_info("Manually reconnecting to Twitch EventSub...");
	EventSub::instance().shutdown();
	EventSub::instance().initialize();
	return true;
}

// Reset WebSocket URL to Default
bool reset_websocket_url(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);

	websocket_url = std::string(DEFAULT_WEBSOCKET_URL);
	obs_log_info("WebSocket URL reset to default: %s", websocket_url.c_str());
	return true;
}

bool validate_websocket_url(obs_properties_t *props, obs_property_t *prop, obs_data_t *settings)
{
	static_cast<void>(props);
	static_cast<void>(prop);

	const char *new_url = obs_data_get_string(settings, "websocket_url");

	if (new_url && *new_url) {
		if (valid_websocket_url(new_url)) {
			websocket_url = std::string(new_url);
			obs_log_info("WebSocket URL updated: %s", websocket_url.c_str());
		} else {
			obs_log_info("Invalid WebSocket URL entered: %s", new_url);
			obs_data_set_string(settings, "websocket_url",
					    websocket_url.c_str()); // Reset to previous valid URL
		}
	}

	return true;
}

// Update settings dynamically
void obs_module_update_settings(obs_data_t *settings)
{
	custom_bet_limit_enabled = obs_data_get_bool(settings, "enable_custom_bet_limit");
	max_bet_limit = static_cast<size_t>(obs_data_get_int(settings, "max_bet_limit"));
	bet_timeout_duration = static_cast<size_t>(obs_data_get_int(settings, "bet_timeout_duration"));

	const char *new_url = obs_data_get_string(settings, "websocket_url");
	if (new_url && *new_url) {
		websocket_url = std::string(new_url);
	} else {
		websocket_url = std::string(DEFAULT_WEBSOCKET_URL);
	}

	EventSub::instance().set_max_bet_limit(custom_bet_limit_enabled ? max_bet_limit : SIZE_MAX);
	EventSub::instance().set_bet_timeout_duration(bet_timeout_duration);

	obs_log_info("Updated WebSocket URL: %s", websocket_url.c_str());
	obs_log_info("Updated Bet Limit: %s",
		     custom_bet_limit_enabled ? std::to_string(max_bet_limit).c_str() : "Disabled");
	obs_log_info("Updated Bet Timeout Duration: %zu seconds", bet_timeout_duration);
}

// Callback when user toggles the custom bet limit
bool toggle_custom_bet_limit(obs_properties_t *props, obs_property_t *prop, void *data)
{
	static_cast<void>(props);
	static_cast<void>(prop);
	static_cast<void>(data);
	custom_bet_limit_enabled = !custom_bet_limit_enabled;
	obs_log_info("Custom Bet Limit %s", custom_bet_limit_enabled ? "Enabled" : "Disabled");
	return true;
}

bool valid_websocket_url(std::string_view url)
{
	static const std::regex ws_regex(WS_URL_REGEX_PATTERN.data());
	return std::regex_match(url.begin(), url.end(), ws_regex);
}

void update_websocket_status(bool connected)
{
	obs_data_t *settings = obs_data_create();
	obs_data_set_string(settings, "ws_status", connected ? "Connected ✅" : "Disconnected ❌");

	// OBS Logging (for debugging and logs)
	obs_log_info("WebSocket Status: %s", connected ? "Connected to Twitch EventSub!" : "WebSocket Disconnected!");

	// Display a message in OBS UI (using OBS_FRONTEND_INFO)
	obs_frontend_push_ui_translation(OBS_FRONTEND_INFO,
					 connected ? "Connected to Twitch EventSub!" : "WebSocket Disconnected!");
}
